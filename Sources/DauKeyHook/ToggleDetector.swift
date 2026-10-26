public struct ToggleDetector: Sendable {
    enum State: Sendable, Equatable { case idle, arming, armed, spoiled }
    private(set) var state: State = .idle
    public init() {}
    public mutating func flagsChanged(_ modifiers: Modifiers) -> Bool {
        let held = modifiers.intersection([.control, .shift, .option, .command, .function])
        switch state {
        case .idle, .arming:
            if held.isEmpty { state = .idle }
            else if held == .control || held == .shift { state = .arming }
            else if held == [.control, .shift] { state = .armed }
            else { state = .spoiled }
        case .armed:
            if held == [.control, .shift] { return false }
            if held.isEmpty || held == .control || held == .shift {
                state = held.isEmpty ? .idle : .spoiled
                return true
            }
            state = .spoiled
        case .spoiled:
            if held.isEmpty { state = .idle }
        }
        return false
    }
    public mutating func disturb() {
        if state == .arming || state == .armed { state = .spoiled }
    }
}
