import DauKeyEngine

/// The typing runtime on the typing thread: V/E, the shortcut and its capture, the current app and its remembered
/// mode, the session, and the context gate with the one output receipt the sender has yet to report on.
///
/// Every physical key-down, key-up and flags change counts once as input for the gate before it is handled. Only
/// events with a text effect open a receipt; context reads wait until the sender reports on it.
public struct TypingCore: Sendable {
    private var session: TypingSession
    private var gate = ContextGate()
    private var enabled: Bool
    private var detector: ShortcutDetector
    private var soundEnabled: Bool
    private var memory: AppMemory
    private var tap: TapState = .starting
    /// Keys and modifiers held, from the physical events seen.
    private var held = HeldInputs()
    /// The capture in progress; nil when inactive.
    private var capture: ShortcutCapture?
    /// The last capture session begun; kept when it ends so snapshots tell which session ended.
    private var captureID: UInt64?
    private var inlineCompletionApp = false
    private var targetIsSpotlight = false
    /// The focused app's process; nil while unknown.
    private var processID: Int32?
    /// Textual output was handed to the sender, which has not reported on it yet.
    private var senderPending = false

    private static let ownBundleID = "com.emizuki.daukey"
    private static let pass = RuntimeResult(decision: .pass, modeChanged: false)

    public init(enabled: Bool, settings: TypingSettings, appMemory: [String: Bool], rules: RuleTables) {
        self.enabled = enabled
        session = TypingSession(options: settings.options, settings: settings.session, rules: rules)
        detector = ShortcutDetector(config: settings.shortcut)
        soundEnabled = settings.soundEnabled
        memory = AppMemory(memory: appMemory, perAppSwitching: settings.perAppSwitching)
    }

    public var snapshot: Snapshot {
        Snapshot(
            enabled: enabled, settings: settings, appMemory: memory.memory, tap: tap,
            shortcutCapture: CaptureSnapshot(id: captureID, phase: capture?.phase ?? .inactive)
        )
    }

    /// The settings in effect, each read from its one owner.
    private var settings: TypingSettings {
        TypingSettings(
            options: session.options, session: session.settings, shortcut: detector.config,
            perAppSwitching: memory.perAppSwitching, soundEnabled: soundEnabled
        )
    }

    // MARK: Physical events

    public mutating func keyDown(_ input: KeyInput) -> RuntimeResult {
        gate.noteInput()
        held.note(.keyDown(input))
        if capture != nil {
            advanceCapture(.keyDown(input))
            return Self.pass
        }
        let shortcut = detector.handle(.keyDown(input))
        if shortcut.toggle { return RuntimeResult(decision: .swallow([]), modeChanged: toggle()) }
        if shortcut.consume { return RuntimeResult(decision: .swallow([]), modeChanged: false) }
        guard enabled else { return Self.pass }
        let event = KeyClassifier.classify(input)
        switch event {
        case .reset:
            // The key's effect on the text is unknown: drop ownership and wait for the host at its new position.
            resetSession(awaitingHostChange: true)
            return Self.pass
        case .endWord:
            _ = session.handle(.endWord)
            return Self.pass
        case .backspace where gate.hasSelection:
            // The host deletes the selection; the text before it is what the session expects.
            return stage(.pass)
        case .char, .backspace:
            let action = session.handle(event, bypassMacro: Self.bypassesMacro(input))
            return stage(OutputPlan.decision(
                for: action, inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: targetIsSpotlight
            ))
        }
    }

    /// Key-ups end the shortcut key's latch; they never reach the session.
    public mutating func keyUp(_ keyCode: UInt16) -> RuntimeResult {
        gate.noteInput()
        held.note(.keyUp(keyCode))
        if capture != nil {
            advanceCapture(.keyUp(keyCode))
            return Self.pass
        }
        let consume = detector.handle(.keyUp(keyCode)).consume
        return RuntimeResult(decision: consume ? .swallow([]) : .pass, modeChanged: false)
    }

    public mutating func flagsChanged(_ modifiers: Modifiers) -> RuntimeResult {
        gate.noteInput()
        held.note(.flagsChanged(modifiers))
        if capture != nil {
            advanceCapture(.flagsChanged(modifiers))
            return Self.pass
        }
        let shortcut = detector.handle(.flagsChanged(modifiers))
        return RuntimeResult(decision: .pass, modeChanged: shortcut.toggle && toggle())
    }

    public mutating func mouseDown() {
        detector.reset()
        resetSession(awaitingHostChange: true)
    }

    public mutating func keyTarget(isSpotlight: Bool) { targetIsSpotlight = isSpotlight }

    // MARK: Output receipt

    /// The sender submitted the output of the last event; the host has yet to show it.
    public mutating func commitSent() {
        guard senderPending else { return }
        gate.didSubmit()
        senderPending = false
    }

    /// The sender could not deliver the output, possibly after part of it: the session no longer knows the text, and
    /// the host may still show the text from before the output.
    public mutating func sendFailed() {
        senderPending = false
        resetSession(awaitingHostChange: true)
    }

    // MARK: Context

    /// A read of the focused text to schedule, at most once per ticket; nil while output waits for the sender, while
    /// V/E is off (turning it on starts a new generation), or while the focused process is unknown.
    public mutating func contextRequest() -> ContextRequest? {
        guard !senderPending, enabled else { return nil }
        return gate.request(projection: session.contextProjection)
    }

    public mutating func handleContext(_ observation: ContextObservation) {
        switch observation {
        case .sample(let sample):
            guard gate.isCurrent(sample.ticket) else { return }
            let projection = session.contextProjection
            let owned = session.canSynchronizeContext(sample.context)
            // A selection after owned text, in an app whose inline suggestions need the baseline workaround.
            let suggestion = inlineCompletionApp && projection.hasOwnedSuffix && owned
            switch gate.accept(sample, projection: projection, ownedSuffixMatches: owned,
                               allowsInlineSuggestion: suggestion) {
            case .ignored:
                break
            case .mismatch:
                resetSession(awaitingHostChange: false)
            case .accepted(let context):
                // Typing replaces a selection that is not such a suggestion; nothing before it is owned.
                if sample.selection.length > 0, !suggestion { _ = session.handle(.reset) }
                if !session.synchronizeContext(context) { resetSession(awaitingHostChange: false) }
            }
        case .invalidated(let ticket):
            // Focus moved within this process; the ticket may predate the current one.
            guard ticket.processID == processID else { return }
            resetSession(awaitingHostChange: false)
        case .unavailable(let ticket):
            guard gate.isCurrent(ticket) else { return }
            gate.markUnavailable()
            session.invalidateContext()
        }
    }

    // MARK: Commands

    public mutating func apply(_ change: SettingsChange) -> RuntimeResult {
        var options = session.options
        switch change {
        case .enabled(let value):
            return setEnabled(value)
        case .inputMethod(let value): options.inputMethod = value
        case .toneStyle(let value): options.toneStyle = value
        case .spelling(let value): options.spelling = value
        case .allowForeignConsonants(let value): options.allowForeignConsonants = value
        case .autoCapitalize(let value):
            var settings = session.settings
            settings.autoCapitalize = value
            session.setSettings(settings)
        case .perAppSwitching(let value):
            memory.setPerAppSwitching(value, enabled: enabled)
        case .soundEnabled(let value):
            soundEnabled = value
        case .shortcut(let config):
            // A new shortcut never fires from keys that are already down.
            detector = ShortcutDetector(config: config)
            detector.waitForRelease(heldModifiers: held.modifiers, heldKeys: held.keys)
        }
        if options != session.options { session.setOptions(options) }
        return Self.pass
    }

    public mutating func setEnabled(_ value: Bool) -> RuntimeResult {
        let changed = value != enabled
        reset()
        enabled = value
        memory.record(value)
        return RuntimeResult(decision: .pass, modeChanged: changed)
    }

    /// The rules apply from the next token; the word being typed is kept.
    public mutating func replaceRules(_ rules: RuleTables) {
        session.setRules(rules)
    }

    /// `processID` is the app's process, or nil when it is unknown; then no context is read until it is known.
    public mutating func appActivated(
        _ bundleID: String?, processID: Int32?, inlineCompletionApp: Bool
    ) -> RuntimeResult {
        detector.reset()
        _ = session.handle(.reset)
        self.processID = processID
        gate.invalidate(processID: processID, awaitingHostChange: false)
        targetIsSpotlight = false
        if bundleID != Self.ownBundleID {
            self.inlineCompletionApp = bundleID != nil && inlineCompletionApp
        }
        let wasEnabled = enabled
        memory.appActivated(bundleID, enabled: &enabled)
        return RuntimeResult(decision: .pass, modeChanged: enabled != wasEnabled)
    }

    /// Returns to the defaults: V, `TypingSettings()` and no remembered apps. The current app stays the target,
    /// with no entry recorded for it; rules stay.
    public mutating func resetToDefaults() -> RuntimeResult {
        let wasEnabled = enabled
        enabled = true
        let defaults = TypingSettings()
        session.setOptions(defaults.options)
        session.setSettings(defaults.session)
        soundEnabled = defaults.soundEnabled
        // Turning switching on records the current app; clearing afterwards leaves no entry.
        memory.setPerAppSwitching(defaults.perAppSwitching, enabled: enabled)
        memory.clearEntries()
        detector = ShortcutDetector(config: defaults.shortcut)
        capture = nil
        resetSession(awaitingHostChange: false)
        return RuntimeResult(decision: .pass, modeChanged: !wasEnabled)
    }

    /// Starts capture session `id`, replacing any other. Physical input then only feeds the capture.
    public mutating func beginShortcutCapture(id: UInt64) {
        capture = ShortcutCapture(heldModifiers: held.modifiers, heldKeys: held.keys)
        captureID = id
    }

    /// Ends capture session `id`; an end for another session changes nothing.
    public mutating func endShortcutCapture(id: UInt64) {
        guard id == captureID, capture != nil else { return }
        finishCapture()
    }

    /// A hook reset: the caret position is unknown.
    public mutating func reset() {
        detector.reset()
        resetSession(awaitingHostChange: false)
    }

    public mutating func setTap(_ value: TapState) { tap = value }
    public mutating func inputSourceChanged() { reset() }

    // MARK: Private

    /// Shift+Space, Shift+Return and Shift+keypad Enter type their delimiter without expanding a macro.
    private static func bypassesMacro(_ input: KeyInput) -> Bool {
        guard input.modifiers.contains(.shift) else { return false }
        switch input.keyCode {
        case 0x31, 0x24, 0x4C: return true
        default: return false
        }
    }

    /// Opens the receipt for an event with a text effect.
    private mutating func stage(_ decision: Decision) -> RuntimeResult {
        senderPending = true
        return RuntimeResult(decision: decision, modeChanged: false, requiresCommit: true)
    }

    /// Toggles V/E for the shortcut; returns true.
    private mutating func toggle() -> Bool {
        enabled.toggle()
        memory.record(enabled)
        resetSession(awaitingHostChange: false)
        return true
    }

    /// Drops the session's words and context and starts a new context generation.
    private mutating func resetSession(awaitingHostChange: Bool) {
        _ = session.handle(.reset)
        gate.invalidate(processID: processID, awaitingHostChange: awaitingHostChange)
    }

    private mutating func advanceCapture(_ event: ShortcutEvent) {
        capture?.handle(event)
        if capture?.phase == .inactive { finishCapture() }
    }

    /// Typing resumes at once; only the shortcut waits until everything held now is released.
    private mutating func finishCapture() {
        capture = nil
        detector.waitForRelease(heldModifiers: held.modifiers, heldKeys: held.keys)
    }
}
