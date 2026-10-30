import Foundation
import Testing
import DauKeyEngine
import DauKeyHook
@testable import DauKey

/// Runs `body` with a defaults suite no other test or app uses, removed afterwards.
@MainActor func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "DauKeyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@MainActor @Suite struct PreferencesStoreTests {
    private let changedRuntime = RuntimePreferences(
        enabled: false,
        settings: TypingSettings(
            options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .off, allowForeignConsonants: true),
            session: SessionSettings(autoCapitalize: true),
            shortcut: ShortcutConfig(modifiers: [.command, .option], keyCode: 0x31),
            perAppSwitching: false,
            soundEnabled: true),
        appMemory: ["com.apple.Safari": false, "com.apple.TextEdit": true])

    @Test func emptyDomainLoadsDefaultsAndNoRules() {
        withIsolatedDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            let loaded = store.load()
            #expect(loaded.runtime == RuntimePreferences())
            #expect(loaded.runtime.enabled)
            #expect(loaded.runtime.settings == TypingSettings())
            #expect(loaded.runtime.appMemory.isEmpty)
            #expect(loaded.language == .vietnamese)
            #expect(!loaded.didShowWelcome)
            let rules = store.loadRules()
            #expect(rules.macros.isEmpty)
            #expect(rules.exclusions.isEmpty)
        }
    }

    @Test func savedSettingsReloadFromTheSameSuite() {
        withIsolatedDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            store.saveRuntime(changedRuntime)
            store.saveLanguage(.english)
            store.saveWelcomeShown(true)
            let loaded = PreferencesStore(defaults: defaults).load()
            #expect(loaded.runtime == changedRuntime)
            #expect(loaded.language == .english)
            #expect(loaded.didShowWelcome)
        }
    }

    @Test func falseBooleansAndDefaultValuesOverwriteEarlierOnes() {
        withIsolatedDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            store.saveRuntime(changedRuntime)
            store.saveLanguage(.english)
            store.saveWelcomeShown(true)
            // Defaults include true booleans; a fresh suite must not be what makes them come back.
            var back = RuntimePreferences()
            back.settings.soundEnabled = false
            back.settings.session.autoCapitalize = false
            back.settings.options.allowForeignConsonants = false
            store.saveRuntime(back)
            store.saveLanguage(.vietnamese)
            store.saveWelcomeShown(false)
            let loaded = PreferencesStore(defaults: defaults).load()
            #expect(loaded.runtime == back)
            #expect(loaded.language == .vietnamese)
            #expect(!loaded.didShowWelcome)
        }
    }

    @Test func settingsUseTheKeysTheAppAlreadyWrites() {
        withIsolatedDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            store.saveRuntime(changedRuntime)
            store.saveLanguage(.english)
            store.saveWelcomeShown(true)
            #expect(defaults.object(forKey: "enabled") as? Bool == false)
            #expect(defaults.string(forKey: "inputMethod") == "vni")
            #expect(defaults.string(forKey: "toneStyle") == "modern")
            #expect(defaults.string(forKey: "spelling") == "off")
            #expect(defaults.object(forKey: "allowForeignConsonants") as? Bool == true)
            #expect(defaults.object(forKey: "autoCapitalize") as? Bool == true)
            #expect(defaults.object(forKey: "perAppSwitching") as? Bool == false)
            #expect(defaults.object(forKey: "soundEnabled") as? Bool == true)
            #expect(defaults.object(forKey: "shortcutModifiers") as? Int == Int(Modifiers([.command, .option]).rawValue))
            #expect(defaults.object(forKey: "shortcutKeyCode") as? Int == 0x31)
            #expect(defaults.dictionary(forKey: "appMemory") as? [String: Bool] == changedRuntime.appMemory)
            #expect(defaults.string(forKey: "appLanguage") == "en")
            #expect(defaults.object(forKey: "didShowWelcome") as? Bool == true)

            var modifierOnly = changedRuntime
            modifierOnly.settings.shortcut = ShortcutConfig()
            store.saveRuntime(modifierOnly)
            #expect(defaults.object(forKey: "shortcutKeyCode") as? Int == -1)
        }
    }

    @Test func settingsWrittenByTheCurrentAppLoad() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: "enabled")
            defaults.set("simpleTelex", forKey: "inputMethod")
            defaults.set("modern", forKey: "toneStyle")
            defaults.set("check", forKey: "spelling")
            defaults.set(true, forKey: "allowForeignConsonants")
            defaults.set(true, forKey: "autoCapitalize")
            defaults.set(false, forKey: "perAppSwitching")
            defaults.set(true, forKey: "soundEnabled")
            defaults.set(Modifiers([.control, .option]).rawValue, forKey: "shortcutModifiers")
            defaults.set(0x00, forKey: "shortcutKeyCode")
            defaults.set(["com.apple.Notes": false], forKey: "appMemory")
            defaults.set("en", forKey: "appLanguage")
            defaults.set(true, forKey: "didShowWelcome")
            let loaded = PreferencesStore(defaults: defaults).load()
            #expect(loaded.runtime == RuntimePreferences(
                enabled: false,
                settings: TypingSettings(
                    options: Options(inputMethod: .simpleTelex, toneStyle: .modern, spelling: .check,
                                     allowForeignConsonants: true),
                    session: SessionSettings(autoCapitalize: true),
                    shortcut: ShortcutConfig(modifiers: [.control, .option], keyCode: 0x00),
                    perAppSwitching: false,
                    soundEnabled: true),
                appMemory: ["com.apple.Notes": false]))
            #expect(loaded.language == .english)
            #expect(loaded.didShowWelcome)
        }
    }

    @Test func storedShortcutOutsideItsRangeLoadsTheDefaultShortcut() {
        let invalid: [(modifiers: Any, keyCode: Any)] = [
            (Int(Modifiers([.command]).rawValue), 70_000),
            (Int(Modifiers([.command]).rawValue), -2),
            (Int(Modifiers([.command]).rawValue), Int.max),
            (Int(Modifiers([.command]).rawValue), "49"),
            (Int(Modifiers([.command]).rawValue), 3.5),
            (300, 0x31),
            (-1, 0x31),
            ("ctrl", 0x31),
        ]
        for value in invalid {
            withIsolatedDefaults { defaults in
                defaults.set(value.modifiers, forKey: "shortcutModifiers")
                defaults.set(value.keyCode, forKey: "shortcutKeyCode")
                defaults.set("vni", forKey: "inputMethod")
                let loaded = PreferencesStore(defaults: defaults).load()
                #expect(loaded.runtime.settings.shortcut == ShortcutConfig())
                #expect(loaded.runtime.settings.options.inputMethod == .vni)
            }
        }
    }

    @Test func wrongTypedFieldsLoadTheirDefaultsAndKeepRuleData() {
        withIsolatedDefaults { defaults in
            let macro = MacroEntry(trigger: "vn", replacement: "Việt Nam")
            let exclusion = ExclusionEntry(word: "been")
            PreferencesStore(defaults: defaults).saveRules(macros: [macro], exclusions: [exclusion])
            defaults.set("no", forKey: "enabled")
            defaults.set(3, forKey: "inputMethod")
            defaults.set("medieval", forKey: "toneStyle")
            defaults.set("strict", forKey: "spelling")
            defaults.set("yes", forKey: "allowForeignConsonants")
            defaults.set(2, forKey: "autoCapitalize")
            defaults.set(["on"], forKey: "perAppSwitching")
            defaults.set("loud", forKey: "soundEnabled")
            defaults.set(["com.apple.Notes": "on"], forKey: "appMemory")
            defaults.set("fr", forKey: "appLanguage")
            defaults.set("yes", forKey: "didShowWelcome")
            let store = PreferencesStore(defaults: defaults)
            let loaded = store.load()
            #expect(loaded.runtime == RuntimePreferences())
            #expect(loaded.language == .vietnamese)
            #expect(!loaded.didShowWelcome)
            let rules = store.loadRules()
            #expect(rules.macros == [macro])
            #expect(rules.exclusions == [exclusion])
            #expect(defaults.data(forKey: "macroEntries") != nil)
        }
    }

    @Test func corruptRuleDataLoadsNoRulesWithoutTouchingSettings() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: "macroEntries")
            defaults.set("words", forKey: "exclusionEntries")
            defaults.set("vni", forKey: "inputMethod")
            let store = PreferencesStore(defaults: defaults)
            let rules = store.loadRules()
            #expect(rules.macros.isEmpty)
            #expect(rules.exclusions.isEmpty)
            #expect(store.load().runtime.settings.options.inputMethod == .vni)
            // Loading never rewrites what it could not read.
            #expect(defaults.data(forKey: "macroEntries") == Data("not json".utf8))
            #expect(defaults.string(forKey: "exclusionEntries") == "words")
        }
    }

    @Test func rulesRoundTripIncludingDraftRows() {
        withIsolatedDefaults { defaults in
            let macros = [
                MacroEntry(trigger: "vn", replacement: " dòng 1, \"quote\"\n dòng 2 "),
                MacroEntry(trigger: "", replacement: ""),
                MacroEntry(trigger: "hn", replacement: ""),
            ]
            let exclusions = [ExclusionEntry(word: "been"), ExclusionEntry(word: "")]
            PreferencesStore(defaults: defaults).saveRules(macros: macros, exclusions: exclusions)
            let rules = PreferencesStore(defaults: defaults).loadRules()
            #expect(rules.macros == macros)
            #expect(rules.macros[0].replacement.unicodeScalars.elementsEqual(macros[0].replacement.unicodeScalars))
            #expect(rules.exclusions == exclusions)
        }
    }

    @Test func ruleDataWrittenByTheCurrentAppLoads() throws {
        try withIsolatedDefaults { defaults in
            let json = """
                [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","trigger":"vn","replacement":"Việt Nam"}]
                """
            defaults.set(Data(json.utf8), forKey: "macroEntries")
            defaults.set(Data(#"[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","word":"docker"}]"#.utf8),
                         forKey: "exclusionEntries")
            let macroID = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
            let exclusionID = try #require(UUID(uuidString: "7F9619FF-8B86-D011-B42D-00C04FC964FF"))
            let rules = PreferencesStore(defaults: defaults).loadRules()
            #expect(rules.macros == [MacroEntry(id: macroID, trigger: "vn", replacement: "Việt Nam")])
            #expect(rules.exclusions == [ExclusionEntry(id: exclusionID, word: "docker")])
        }
    }

    @Test func twoSuitesDoNotAffectEachOther() {
        withIsolatedDefaults { first in
            withIsolatedDefaults { second in
                let firstStore = PreferencesStore(defaults: first)
                let secondStore = PreferencesStore(defaults: second)
                firstStore.saveRuntime(changedRuntime)
                firstStore.saveLanguage(.english)
                firstStore.saveWelcomeShown(true)
                firstStore.saveRules(macros: [MacroEntry(trigger: "vn", replacement: "Việt Nam")],
                                     exclusions: [ExclusionEntry(word: "been")])
                let loaded = secondStore.load()
                #expect(loaded.runtime == RuntimePreferences())
                #expect(loaded.language == .vietnamese)
                #expect(!loaded.didShowWelcome)
                #expect(secondStore.loadRules().macros.isEmpty)
                #expect(secondStore.loadRules().exclusions.isEmpty)
                #expect(PreferencesStore(defaults: first).load().runtime == changedRuntime)
            }
        }
    }
}
