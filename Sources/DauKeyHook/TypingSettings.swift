import DauKeyEngine

/// The settings the typing runtime applies; the defaults are what a reset returns to.
public struct TypingSettings: Sendable, Equatable {
    public var options: Options
    public var session: SessionSettings
    public var shortcut: ShortcutConfig
    public var perAppSwitching: Bool
    public var soundEnabled: Bool

    public init(
        options: Options = Options(),
        session: SessionSettings = SessionSettings(),
        shortcut: ShortcutConfig = ShortcutConfig(),
        perAppSwitching: Bool = true,
        soundEnabled: Bool = false
    ) {
        self.options = options
        self.session = session
        self.shortcut = shortcut
        self.perAppSwitching = perAppSwitching
        self.soundEnabled = soundEnabled
    }
}

/// One setting changed by the user; the runtime applies each change to its current state.
public enum SettingsChange: Sendable, Equatable {
    case enabled(Bool)
    case inputMethod(InputMethod)
    case toneStyle(ToneStyle)
    case spelling(Spelling)
    case allowForeignConsonants(Bool)
    case autoCapitalize(Bool)
    case perAppSwitching(Bool)
    case soundEnabled(Bool)
    case shortcut(ShortcutConfig)
}
