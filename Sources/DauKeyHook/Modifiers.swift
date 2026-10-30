public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
    public static let capsLock = Self(rawValue: 1 << 5)
}

public struct ShortcutConfig: Equatable, Hashable, Sendable {
    public var modifiers: Modifiers
    public var keyCode: UInt16?

    public init(modifiers: Modifiers = [.control, .shift], keyCode: UInt16? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }
}
