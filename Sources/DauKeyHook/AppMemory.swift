public struct AppMemory: Sendable {
    public private(set) var memory: [String: Bool]
    /// The external app V/E applies to; activating DauKey itself does not change it.
    private(set) var current: String?
    public private(set) var perAppSwitching: Bool
    public init(memory: [String: Bool], perAppSwitching: Bool = true) {
        self.memory = memory
        self.perAppSwitching = perAppSwitching
    }
    /// Always follows the external target; restores and records its mode only while per-app switching is on.
    public mutating func appActivated(_ bundleID: String?, enabled: inout Bool) {
        guard bundleID != "com.emizuki.daukey" else { return }
        current = bundleID
        guard perAppSwitching, let bundleID else { return }
        enabled = memory[bundleID] ?? enabled
        memory[bundleID] = enabled
    }
    public mutating func record(_ enabled: Bool) {
        guard perAppSwitching, let current else { return }
        memory[current] = enabled
    }
    /// Turning switching on records the mode in use for the current app instead of restoring its old one.
    public mutating func setPerAppSwitching(_ value: Bool, enabled: Bool) {
        guard value != perAppSwitching else { return }
        perAppSwitching = value
        record(enabled)
    }
    /// Forgets every remembered app; the current external target stays.
    public mutating func clearEntries() {
        memory.removeAll()
    }
}
