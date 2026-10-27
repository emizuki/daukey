import DauKeyEngine

public struct TypingCore: Sendable {
    private var engine: Engine
    private var enabled: Bool
    private var toggle: ToggleDetector
    private var memory: AppMemory
    private var tap: TapState = .starting
    private var currentNeedsInlineCompletionWorkaround = false
    private var targetIsSpotlight = false
    public var perAppSwitching: Bool
    public var soundEnabled: Bool

    public init(
        enabled: Bool,
        options: Options,
        appMemory: [String: Bool],
        perAppSwitching: Bool = true,
        soundEnabled: Bool = false,
        shortcut: ShortcutConfig = ShortcutConfig()
    ) {
        self.enabled = enabled
        self.engine = Engine(options: options)
        self.memory = AppMemory(memory: appMemory)
        self.perAppSwitching = perAppSwitching
        self.soundEnabled = soundEnabled
        self.toggle = ToggleDetector(config: shortcut)
    }

    public var snapshot: Snapshot {
        Snapshot(
            enabled: enabled,
            options: engine.options,
            appMemory: memory.memory,
            tap: tap,
            perAppSwitching: perAppSwitching,
            soundEnabled: soundEnabled,
            shortcut: toggle.config
        )
    }

    public mutating func keyDown(_ input: KeyInput) -> Decision {
        if toggle.matchesKeyDown(input) {
            enabled.toggle()
            if perAppSwitching { memory.record(enabled) }
            _ = engine.handle(.reset)
            return .swallow([])
        }
        toggle.disturb()
        guard enabled else { return .pass }
        return OutputPlan.decision(for: engine.handle(KeyClassifier.classify(input)),
            inlineCompletionApp: currentNeedsInlineCompletionWorkaround, targetIsSpotlight: targetIsSpotlight)
    }

    public mutating func flagsChanged(_ modifiers: Modifiers) -> Bool {
        guard toggle.flagsChanged(modifiers) else { return false }
        enabled.toggle()
        if perAppSwitching { memory.record(enabled) }
        _ = engine.handle(.reset)
        return true
    }

    public mutating func mouseDown() { reset() }
    public mutating func keyTarget(isSpotlight: Bool) { targetIsSpotlight = isSpotlight }
    public mutating func appActivated(_ bundleID: String?, inlineCompletionApp: Bool) {
        reset()
        targetIsSpotlight = false
        if bundleID != "com.emizuki.daukey" {
            currentNeedsInlineCompletionWorkaround = bundleID != nil && inlineCompletionApp
        }
        if perAppSwitching {
            memory.appActivated(bundleID, enabled: &enabled)
        }
    }

    public mutating func setEnabled(_ value: Bool) {
        reset()
        enabled = value
        if perAppSwitching { memory.record(value) }
    }

    public mutating func setOptions(_ options: Options) {
        toggle.disturb()
        engine.options = options
    }

    public mutating func setPerAppSwitching(_ value: Bool) {
        perAppSwitching = value
    }

    public mutating func setSoundEnabled(_ value: Bool) {
        soundEnabled = value
    }

    public mutating func setShortcut(_ config: ShortcutConfig) {
        toggle = ToggleDetector(config: config)
    }

    public mutating func resetToDefaults() {
        enabled = true
        engine.options = Options()
        memory = AppMemory(memory: [:])
        perAppSwitching = true
        soundEnabled = false
        toggle = ToggleDetector(config: ShortcutConfig())
        reset()
    }

    public mutating func reset() {
        toggle.disturb()
        _ = engine.handle(.reset)
    }

    public mutating func setTap(_ value: TapState) { tap = value }
    public mutating func inputSourceChanged() { reset() }
}
