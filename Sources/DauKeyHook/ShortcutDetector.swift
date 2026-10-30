/// A physical input event as the shortcut detector and capture see it.
public enum ShortcutEvent: Sendable {
    case keyDown(KeyInput)
    case keyUp(UInt16)
    case flagsChanged(Modifiers)
}

/// What to do with an event: toggle V/E, and whether to swallow the original event.
public struct ShortcutDecision: Equatable, Sendable {
    public var toggle: Bool
    public var consume: Bool

    public init(toggle: Bool, consume: Bool) {
        self.toggle = toggle
        self.consume = consume
    }

    public static let pass = ShortcutDecision(toggle: false, consume: false)
}

extension Modifiers {
    /// Modifiers that make up a shortcut chord; Caps Lock is a lock state, not part of a chord.
    static let chord: Modifiers = [.control, .shift, .option, .command, .function]
}

/// Keys and modifiers currently held, from physical events; its key storage is reused.
struct HeldInputs: Sendable {
    private(set) var modifiers: Modifiers = []
    private(set) var keys: Set<UInt16>

    init() {
        keys = []
        keys.reserveCapacity(8)
    }

    var isEmpty: Bool { modifiers.isEmpty && keys.isEmpty }

    mutating func replace(modifiers: Modifiers, keys: Set<UInt16>) {
        self.modifiers = modifiers.intersection(.chord)
        self.keys.removeAll(keepingCapacity: true)
        self.keys.formUnion(keys)
    }

    mutating func note(_ event: ShortcutEvent) {
        switch event {
        case .keyDown(let input): keys.insert(input.keyCode)
        case .keyUp(let keyCode): keys.remove(keyCode)
        case .flagsChanged(let modifiers): self.modifiers = modifiers.intersection(.chord)
        }
    }
}

/// Detects the V/E shortcut in physical events.
///
/// A modifier-only chord toggles once, when every modifier is released after exactly the chord was held, with no
/// other modifier or key in between; flags events always pass. A modifier+key chord toggles at the first key-down
/// that matches exactly and swallows it, its repeats and its key-up; keys pressed later do not undo the toggle and
/// nothing is replayed.
public struct ShortcutDetector: Sendable {
    private enum ChordState: Sendable { case idle, arming, armed, spoiled }

    public let config: ShortcutConfig
    private let target: Modifiers
    private var chord: ChordState = .idle
    /// The key whose matching key-down was swallowed; its repeats and key-up are swallowed too.
    private var latchedKey: UInt16?
    /// Detection waits for a clean release while set; `held` tracks what is still down.
    private var waiting = false
    private var held = HeldInputs()

    public init(config: ShortcutConfig) {
        self.config = config
        target = config.modifiers.intersection(.chord)
    }

    public mutating func handle(_ event: ShortcutEvent) -> ShortcutDecision {
        let consume = consumesLatched(event)
        if waiting {
            held.note(event)
            if held.isEmpty { waiting = false }
            return ShortcutDecision(toggle: false, consume: consume)
        }
        if consume { return ShortcutDecision(toggle: false, consume: true) }
        if let keyCode = config.keyCode {
            guard case .keyDown(let input) = event, !input.isRepeat, input.keyCode == keyCode,
                  input.modifiers.intersection(.chord) == target else { return .pass }
            latchedKey = keyCode
            return ShortcutDecision(toggle: true, consume: true)
        }
        return ShortcutDecision(toggle: modifierOnly(event), consume: false)
    }

    /// Forgets the chord in progress and the latched key.
    public mutating func reset() {
        chord = .idle
        latchedKey = nil
        waiting = false
        held.replace(modifiers: [], keys: [])
    }

    /// Defers detection until every given modifier and key, and anything pressed meanwhile, is released.
    /// The latched key stays swallowed only if it is still held.
    public mutating func waitForRelease(heldModifiers: Modifiers, heldKeys: Set<UInt16>) {
        chord = .idle
        if let latchedKey, !heldKeys.contains(latchedKey) { self.latchedKey = nil }
        held.replace(modifiers: heldModifiers, keys: heldKeys)
        waiting = !held.isEmpty
    }

    /// Whether the event belongs to the latched key; a fresh press of that key means its key-up was missed.
    private mutating func consumesLatched(_ event: ShortcutEvent) -> Bool {
        guard let latchedKey else { return false }
        switch event {
        case .keyDown(let input) where input.keyCode == latchedKey:
            if input.isRepeat { return true }
            self.latchedKey = nil
            return false
        case .keyUp(let keyCode) where keyCode == latchedKey:
            self.latchedKey = nil
            return true
        default:
            return false
        }
    }

    /// Advances the modifier-only chord; returns whether it completed.
    private mutating func modifierOnly(_ event: ShortcutEvent) -> Bool {
        guard !target.isEmpty else { return false }
        switch event {
        case .keyDown:
            if chord == .arming || chord == .armed { chord = .spoiled }
        case .keyUp:
            break
        case .flagsChanged(let modifiers):
            let held = modifiers.intersection(.chord)
            switch chord {
            case .idle, .arming:
                if held.isEmpty { chord = .idle }
                else if held == target { chord = .armed }
                else if target.isSuperset(of: held) { chord = .arming }
                else { chord = .spoiled }
            case .armed:
                if held.isEmpty {
                    chord = .idle
                    return true
                }
                if !target.isSuperset(of: held) { chord = .spoiled }
            case .spoiled:
                if held.isEmpty { chord = .idle }
            }
        }
        return false
    }
}
