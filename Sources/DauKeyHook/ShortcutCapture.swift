/// Where shortcut capture is. `.recorded` keeps its result until the capture is cancelled or ended.
public enum CapturePhase: Sendable, Equatable {
    case inactive
    case waitingForRelease
    case recording
    case recorded(ShortcutConfig)
}

/// The capture state the core publishes: the capture session it belongs to, if any, and its phase.
public struct CaptureSnapshot: Sendable, Equatable {
    public var id: UInt64?
    public var phase: CapturePhase

    public init(id: UInt64? = nil, phase: CapturePhase = .inactive) {
        self.id = id
        self.phase = phase
    }
}

/// Records a shortcut chord from physical events.
///
/// Keys held when capture starts must be released first. A chord records when everything in it is released: a
/// modifier+key chord with the modifiers its key went down with, or a modifier-only chord with every modifier it
/// held. Escape cancels; chords that cannot be a shortcut are dropped and recording continues.
public struct ShortcutCapture: Sendable {
    public private(set) var phase: CapturePhase
    private var held = HeldInputs()
    /// Every chord modifier held since the chord started.
    private var modifiers: Modifiers = []
    private var key: UInt16?
    private var keyModifiers: Modifiers = []
    /// Cleared when the chord has a second non-modifier key, which a shortcut cannot hold.
    private var usable = true

    private static let escape: UInt16 = 0x35
    /// A modifier-only chord needs two of these; the function flag also marks arrow and function keys, so it does
    /// not count.
    private static let primary: Modifiers = [.control, .shift, .option, .command]
    /// A modifier+key chord needs one of these; Shift with a key types a character.
    private static let keyPrimary: Modifiers = [.control, .option, .command]

    public init(heldModifiers: Modifiers, heldKeys: Set<UInt16>) {
        held.replace(modifiers: heldModifiers, keys: heldKeys)
        phase = held.isEmpty ? .recording : .waitingForRelease
    }

    public mutating func handle(_ event: ShortcutEvent) {
        guard phase == .waitingForRelease || phase == .recording else { return }
        if case .keyDown(let input) = event, input.keyCode == Self.escape {
            cancel()
            return
        }
        held.note(event)
        if phase == .waitingForRelease {
            if held.isEmpty { phase = .recording }
            return
        }
        switch event {
        case .keyDown(let input) where !input.isRepeat:
            let pressed = input.modifiers.intersection(.chord)
            modifiers.formUnion(pressed)
            if key == nil {
                key = input.keyCode
                keyModifiers = pressed
            } else if key != input.keyCode {
                usable = false
            }
        case .flagsChanged:
            modifiers.formUnion(held.modifiers)
        case .keyDown, .keyUp:
            break
        }
        guard held.isEmpty else { return }
        if let config = recordedConfig() { phase = .recorded(config) }
        modifiers = []
        key = nil
        keyModifiers = []
        usable = true
    }

    public mutating func cancel() {
        phase = .inactive
    }

    private func recordedConfig() -> ShortcutConfig? {
        guard usable else { return nil }
        if let key {
            guard !keyModifiers.isDisjoint(with: Self.keyPrimary) else { return nil }
            return ShortcutConfig(modifiers: keyModifiers, keyCode: key)
        }
        guard modifiers.intersection(Self.primary).rawValue.nonzeroBitCount >= 2 else { return nil }
        return ShortcutConfig(modifiers: modifiers, keyCode: nil)
    }
}
