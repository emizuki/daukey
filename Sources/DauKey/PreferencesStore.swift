import Foundation
import DauKeyEngine
import DauKeyHook

/// What the typing runtime starts with and saves back as it applies changes.
struct RuntimePreferences: Equatable, Sendable {
    var enabled: Bool
    var settings: TypingSettings
    var appMemory: [String: Bool]

    init(enabled: Bool = true, settings: TypingSettings = TypingSettings(), appMemory: [String: Bool] = [:]) {
        self.enabled = enabled
        self.settings = settings
        self.appMemory = appMemory
    }
}

/// The preferences read at launch, apart from rule rows, which the rule editor loads.
struct StartupSettings: Equatable, Sendable {
    var runtime: RuntimePreferences
    var language: AppLanguage
    var didShowWelcome: Bool
}

/// Reads and writes preferences in one injected defaults domain, one key per setting.
///
/// A value of the wrong type or out of range loads as that setting's default and is left in place until the setting
/// is saved again; it never affects another setting or the rule rows.
@MainActor final class PreferencesStore {
    private enum Key {
        static let enabled = "enabled"
        static let inputMethod = "inputMethod"
        static let toneStyle = "toneStyle"
        static let spelling = "spelling"
        static let allowForeignConsonants = "allowForeignConsonants"
        static let autoCapitalize = "autoCapitalize"
        static let perAppSwitching = "perAppSwitching"
        static let soundEnabled = "soundEnabled"
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let appMemory = "appMemory"
        static let appLanguage = "appLanguage"
        static let didShowWelcome = "didShowWelcome"
        static let macroEntries = "macroEntries"
        static let exclusionEntries = "exclusionEntries"
    }

    /// The stored `shortcutKeyCode` of a shortcut without a key.
    private static let noKeyCode = -1

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> StartupSettings {
        let fallback = TypingSettings()
        let options = Options(
            inputMethod: string(Key.inputMethod).flatMap(InputMethod.init(rawValue:))
                ?? fallback.options.inputMethod,
            toneStyle: string(Key.toneStyle).flatMap(Self.toneStyle) ?? fallback.options.toneStyle,
            spelling: string(Key.spelling).flatMap(Self.spelling) ?? fallback.options.spelling,
            allowForeignConsonants: bool(Key.allowForeignConsonants) ?? fallback.options.allowForeignConsonants)
        let settings = TypingSettings(
            options: options,
            session: SessionSettings(autoCapitalize: bool(Key.autoCapitalize) ?? fallback.session.autoCapitalize),
            shortcut: shortcut() ?? fallback.shortcut,
            perAppSwitching: bool(Key.perAppSwitching) ?? fallback.perAppSwitching,
            soundEnabled: bool(Key.soundEnabled) ?? fallback.soundEnabled)
        let defaultRuntime = RuntimePreferences()
        return StartupSettings(
            runtime: RuntimePreferences(
                enabled: bool(Key.enabled) ?? defaultRuntime.enabled,
                settings: settings,
                appMemory: defaults.object(forKey: Key.appMemory) as? [String: Bool] ?? defaultRuntime.appMemory),
            language: string(Key.appLanguage).flatMap(AppLanguage.init(rawValue:)) ?? .vietnamese,
            didShowWelcome: bool(Key.didShowWelcome) ?? false)
    }

    /// The stored rule rows, drafts included, in table order; unreadable data loads as no rows.
    func loadRules() -> (macros: [MacroEntry], exclusions: [ExclusionEntry]) {
        (decode(Key.macroEntries) ?? [], decode(Key.exclusionEntries) ?? [])
    }

    func saveRuntime(_ value: RuntimePreferences) {
        let options = value.settings.options
        defaults.set(value.enabled, forKey: Key.enabled)
        defaults.set(options.inputMethod.rawValue, forKey: Key.inputMethod)
        defaults.set(Self.name(of: options.toneStyle), forKey: Key.toneStyle)
        defaults.set(Self.name(of: options.spelling), forKey: Key.spelling)
        defaults.set(options.allowForeignConsonants, forKey: Key.allowForeignConsonants)
        defaults.set(value.settings.session.autoCapitalize, forKey: Key.autoCapitalize)
        defaults.set(value.settings.perAppSwitching, forKey: Key.perAppSwitching)
        defaults.set(value.settings.soundEnabled, forKey: Key.soundEnabled)
        defaults.set(Int(value.settings.shortcut.modifiers.rawValue), forKey: Key.shortcutModifiers)
        defaults.set(value.settings.shortcut.keyCode.map(Int.init) ?? Self.noKeyCode, forKey: Key.shortcutKeyCode)
        defaults.set(value.appMemory, forKey: Key.appMemory)
    }

    /// Saves every row as it is, drafts included.
    func saveRules(macros: [MacroEntry], exclusions: [ExclusionEntry]) {
        encode(macros, Key.macroEntries)
        encode(exclusions, Key.exclusionEntries)
    }

    func saveLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Key.appLanguage)
    }

    func saveWelcomeShown(_ shown: Bool) {
        defaults.set(shown, forKey: Key.didShowWelcome)
    }

    private func bool(_ key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    /// Unlike `UserDefaults.string(forKey:)`, does not turn a stored number into a string.
    private func string(_ key: String) -> String? {
        defaults.object(forKey: key) as? String
    }

    /// The stored shortcut, or nil when either of its two values is missing or out of range: half of a stored
    /// shortcut is not one the user chose.
    private func shortcut() -> ShortcutConfig? {
        guard let modifiers = (defaults.object(forKey: Key.shortcutModifiers) as? Int).flatMap(UInt8.init(exactly:)),
              let keyCode = defaults.object(forKey: Key.shortcutKeyCode) as? Int else { return nil }
        if keyCode == Self.noKeyCode { return ShortcutConfig(modifiers: Modifiers(rawValue: modifiers), keyCode: nil) }
        guard let key = UInt16(exactly: keyCode) else { return nil }
        return ShortcutConfig(modifiers: Modifiers(rawValue: modifiers), keyCode: key)
    }

    private func decode<Row: Decodable>(_ key: String) -> [Row]? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Row].self, from: $0) }
    }

    private func encode<Row: Encodable>(_ rows: [Row], _ key: String) {
        // Rows hold only strings and UUIDs, which always encode.
        guard let data = try? JSONEncoder().encode(rows) else { return }
        defaults.set(data, forKey: key)
    }

    private static func toneStyle(_ name: String) -> ToneStyle? {
        switch name {
        case "old": .old
        case "modern": .modern
        default: nil
        }
    }

    private static func name(of toneStyle: ToneStyle) -> String {
        switch toneStyle {
        case .old: "old"
        case .modern: "modern"
        }
    }

    private static func spelling(_ name: String) -> Spelling? {
        switch name {
        case "off": .off
        case "check": .check
        case "checkAndRestore": .checkAndRestore
        default: nil
        }
    }

    private static func name(of spelling: Spelling) -> String {
        switch spelling {
        case .off: "off"
        case .check: "check"
        case .checkAndRestore: "checkAndRestore"
        }
    }
}
