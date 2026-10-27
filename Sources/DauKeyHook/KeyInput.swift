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
    case backspaces(Int), selectBackward(Int), text(String)
}
public enum Decision: Equatable, Sendable {
    case pass, swallow([OutputStep]), passAfter([OutputStep])
}
public struct Snapshot: Equatable, Sendable {
    public let enabled: Bool
    public let options: Options
    public let appMemory: [String: Bool]
    public let tap: TapState
    public let perAppSwitching: Bool
    public let soundEnabled: Bool
    public let shortcut: ShortcutConfig

    public init(
        enabled: Bool,
        options: Options,
        appMemory: [String: Bool],
        tap: TapState,
        perAppSwitching: Bool = true,
        soundEnabled: Bool = false,
        shortcut: ShortcutConfig = ShortcutConfig()
    ) {
        self.enabled = enabled
        self.options = options
        self.appMemory = appMemory
        self.tap = tap
        self.perAppSwitching = perAppSwitching
        self.soundEnabled = soundEnabled
        self.shortcut = shortcut
    }
}
public enum TapState: Equatable, Sendable {
    case starting, running, noPermission, unavailable
}
