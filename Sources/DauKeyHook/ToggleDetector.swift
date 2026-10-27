public struct ToggleDetector: Sendable {
    enum State: Sendable, Equatable { case idle, arming, armed, spoiled }
    private(set) var state: State = .idle
    public var config: ShortcutConfig

    public init(config: ShortcutConfig = ShortcutConfig()) {
        self.config = config
    }

    public mutating func flagsChanged(_ modifiers: Modifiers) -> Bool {
        guard config.keyCode == nil else { return false }
        let target = config.modifiers.intersection([.control, .shift, .option, .command, .function])
        guard !target.isEmpty else { return false }
        let held = modifiers.intersection([.control, .shift, .option, .command, .function])
        switch state {
        case .idle, .arming:
            if held.isEmpty { state = .idle }
            else if target.contains(held) && held != target { state = .arming }
            else if held == target { state = .armed }
            else { state = .spoiled }
        case .armed:
            if held == target { return false }
            if held.isEmpty || (target.contains(held) && held != target) {
                state = held.isEmpty ? .idle : .spoiled
                return true
            }
            state = .spoiled
        case .spoiled:
            if held.isEmpty { state = .idle }
        }
        return false
    }

    public mutating func matchesKeyDown(_ input: KeyInput) -> Bool {
        guard let targetKey = config.keyCode else { return false }
        let targetMods = config.modifiers.intersection([.control, .shift, .option, .command, .function])
        let held = input.modifiers.intersection([.control, .shift, .option, .command, .function])
        if input.keyCode == targetKey && held == targetMods {
            return true
        }
        disturb()
        return false
    }

    public mutating func disturb() {
        if state == .arming || state == .armed { state = .spoiled }
    }
}
