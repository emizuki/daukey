public struct AppMemory: Sendable {
    public private(set) var memory: [String: Bool]
    private(set) var current: String?
    public init(memory: [String: Bool]) { self.memory = memory }
    public mutating func appActivated(_ bundleID: String?, enabled: inout Bool) {
        guard bundleID != "com.emizuki.daukey" else { return }
        current = bundleID
        guard let bundleID else { return }
        enabled = memory[bundleID] ?? enabled
        memory[bundleID] = enabled
    }
    public mutating func record(_ enabled: Bool) {
        if let current { memory[current] = enabled }
    }
}
