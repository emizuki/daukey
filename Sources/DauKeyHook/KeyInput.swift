import DauKeyEngine

public struct KeyInput: Sendable {
    public let keyCode: UInt16
    public let modifiers: Modifiers
    public let characters: String
    public init(keyCode: UInt16, modifiers: Modifiers, characters: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
    }
}
public enum OutputStep: Equatable, Sendable {
    case backspaces(Int), text(String)
}
public enum Decision: Equatable, Sendable {
    case pass, swallow([OutputStep]), passAfter([OutputStep])
}
public struct Snapshot: Equatable, Sendable {
    public let enabled: Bool
    public let options: Options
    public let appMemory: [String: Bool]
    public let tap: TapState
    public init(enabled: Bool, options: Options, appMemory: [String: Bool], tap: TapState) {
        self.enabled = enabled
        self.options = options
        self.appMemory = appMemory
        self.tap = tap
    }
}
public enum TapState: Equatable, Sendable {
    case starting, running, noPermission, unavailable
}
