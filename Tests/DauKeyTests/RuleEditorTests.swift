import Foundation
import Testing
import DauKeyEngine
@testable import DauKey

/// An editor on an isolated defaults suite that records what it emits.
@MainActor private final class Harness {
    let defaults: UserDefaults
    let store: PreferencesStore
    private(set) var emitted: [RuleTables] = []
    private(set) var editor: RuleEditorModel!

    init(_ defaults: UserDefaults) {
        self.defaults = defaults
        store = PreferencesStore(defaults: defaults)
        reload()
    }

    /// A new editor on the same suite, as after a relaunch.
    func reload() {
        emitted = []
        editor = RuleEditorModel(store: PreferencesStore(defaults: defaults)) { [unowned self] in self.emitted.append($0) }
    }

    var storedRules: Data? { defaults.data(forKey: "macroEntries") }
    var storedExclusions: Data? { defaults.data(forKey: "exclusionEntries") }

    func setMacro(_ id: UUID, _ trigger: String, _ replacement: String) {
        editor.updateMacro(MacroEntry(id: id, trigger: trigger, replacement: replacement))
    }

    @discardableResult func addMacro(_ trigger: String, _ replacement: String) -> UUID {
        let id = editor.addMacro()
        setMacro(id, trigger, replacement)
        return id
    }

    @discardableResult func addExclusion(_ word: String) -> UUID {
        let id = editor.addExclusion()
        editor.updateExclusion(ExclusionEntry(id: id, word: word))
        return id
    }
}

/// What the typing runtime puts on screen for `text` typed with `tables`, starting a new session.
private func typed(_ text: String, rules tables: RuleTables) -> String {
    var session = TypingSession(rules: tables)
    var screen: [Character] = []
    for character in text {
        switch session.handle(.char(character)) {
        case .passThrough:
            screen.append(character)
        case .replace(let deleteCount, let insert):
            screen.removeLast(deleteCount)
            screen.append(contentsOf: insert)
        case .replaceThenPass(let deleteCount, let insert):
            screen.removeLast(deleteCount)
            screen.append(contentsOf: insert)
            screen.append(character)
        }
    }
    return String(screen)
}

@MainActor @Suite struct RuleEditorTests {
    @Test func defaultTablesAreEmpty() {
        withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            #expect(harness.editor.macroEntries.isEmpty)
            #expect(harness.editor.exclusionEntries.isEmpty)
            #expect(harness.editor.tables == RuleTables())
            #expect(typed("vn ", rules: harness.editor.tables) == "vn ")
            #expect(harness.emitted.isEmpty)
            #expect(harness.storedRules == nil)
            #expect(harness.storedExclusions == nil)
        }
    }

    @Test func initCompilesStoredRulesWithoutPersistingOrEmitting() {
        withIsolatedDefaults { defaults in
            PreferencesStore(defaults: defaults).saveRules(
                macros: [MacroEntry(trigger: "vn", replacement: "Việt Nam"), MacroEntry(trigger: "x", replacement: "")],
                exclusions: [ExclusionEntry(word: "been")])
            let before = (defaults.data(forKey: "macroEntries"), defaults.data(forKey: "exclusionEntries"))
            let harness = Harness(defaults)
            #expect(harness.emitted.isEmpty)
            #expect(harness.storedRules == before.0)
            #expect(harness.storedExclusions == before.1)
            #expect(harness.editor.macroEntries.count == 2)
            #expect(harness.editor.tables == RuleTables(macros: [MacroRule(trigger: "vn", replacement: "Việt Nam")],
                                                        exclusions: ["been"]))
            #expect(typed("vn ", rules: harness.editor.tables) == "Việt Nam ")
            #expect(typed("been ", rules: harness.editor.tables) == "been ")
        }
    }

    @Test func eachEditPersistsAndEmitsTheCompiledTablesOnce() {
        withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let id = harness.editor.addMacro()
            #expect(harness.emitted.count == 1)
            harness.setMacro(id, "vn", "Việt Nam")
            #expect(harness.emitted.count == 2)
            #expect(harness.emitted.last == harness.editor.tables)
            #expect(harness.editor.tables.replacement(for: "vn") == "Việt Nam")
            let word = harness.editor.addExclusion()
            harness.editor.updateExclusion(ExclusionEntry(id: word, word: "been"))
            #expect(harness.emitted.count == 4)
            #expect(harness.emitted.last == harness.editor.tables)
            #expect(harness.editor.tables.excludes("BEEN"))
            harness.editor.removeMacros([id])
            harness.editor.removeExclusions([word])
            #expect(harness.emitted.count == 6)
            #expect(harness.editor.tables == RuleTables())
            #expect(PreferencesStore(defaults: defaults).loadRules().macros.isEmpty)
        }
    }

    @Test func editsThatChangeNothingDoNotPersistOrEmit() {
        withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let id = harness.addMacro("vn", "Việt Nam")
            let word = harness.addExclusion("been")
            let count = harness.emitted.count
            harness.setMacro(id, "vn", "Việt Nam")
            harness.setMacro(UUID(), "hn", "Hà Nội")
            harness.editor.updateExclusion(ExclusionEntry(id: word, word: "been"))
            harness.editor.updateExclusion(ExclusionEntry(word: "test"))
            harness.editor.removeMacros([UUID()])
            harness.editor.removeExclusions([])
            #expect(harness.emitted.count == count)
            #expect(harness.editor.macroEntries.map(\.id) == [id])
            #expect(harness.editor.exclusionEntries.map(\.id) == [word])
        }
    }

    @Test func incompleteRowsStayAfterOtherEditsAndReloadButAreInactive() {
        withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let blank = harness.editor.addMacro()
            let triggerOnly = harness.addMacro("vn", "")
            let spaced = harness.addMacro("v n", "Việt Nam")
            let complete = harness.addMacro("hn", "Hà Nội")
            let blankWord = harness.editor.addExclusion()
            let spacedWord = harness.addExclusion("be en")
            let word = harness.addExclusion("been")
            harness.reload()
            let editor = harness.editor!
            #expect(editor.macroEntries.map(\.id) == [blank, triggerOnly, spaced, complete])
            #expect(editor.macroEntries[1].trigger == "vn")
            #expect(editor.exclusionEntries.map(\.id) == [blankWord, spacedWord, word])
            #expect(editor.tables == RuleTables(macros: [MacroRule(trigger: "hn", replacement: "Hà Nội")],
                                                exclusions: ["been"]))
            #expect(typed("vn hn ", rules: editor.tables) == "vn Hà Nội ")
        }
    }

    @Test func editorCollisionsLetTheLastRowWin() {
        withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            harness.addMacro("vn", "A")
            harness.addMacro("VN", "B")
            harness.addMacro("vn", "")
            #expect(harness.editor.tables.replacement(for: "vn") == "B")
            #expect(typed("vn ", rules: harness.editor.tables) == "B ")
            let nfd = "vie\u{0323}\u{0302}t"
            harness.addMacro("việt", "nfc")
            harness.addMacro(nfd, "nfd")
            #expect(harness.editor.tables.replacement(for: "Việt") == "nfd")
            harness.reload()
            #expect(harness.editor.tables.replacement(for: "vn") == "B")
            #expect(harness.editor.tables.replacement(for: "việt") == "nfd")
        }
    }

    @Test func importUpdatesWinningCollisionRow() throws {
        try withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let first = harness.addMacro("vn", "A")
            let winner = harness.addMacro("VN", "B")
            let draft = harness.editor.addMacro()
            let count = harness.emitted.count
            try harness.editor.importMacrosCSV("vn,C")
            #expect(harness.emitted.count == count + 1)
            #expect(harness.emitted.last == harness.editor.tables)
            #expect(typed("vn ", rules: harness.editor.tables) == "C ")
            let entries = harness.editor.macroEntries
            #expect(entries.map(\.id) == [first, winner, draft])
            #expect(entries[0].replacement == "A")
            #expect(entries[1].replacement == "C")
            harness.reload()
            #expect(harness.editor.macroEntries.map(\.id) == [first, winner, draft])
            #expect(harness.editor.macroEntries[1].replacement == "C")
            #expect(typed("vn ", rules: harness.editor.tables) == "C ")
        }
    }

    @Test func importMatchesCanonicallyEquivalentAndCaseVariantTriggers() throws {
        try withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let nfd = harness.addMacro("Vie\u{0323}\u{0302}t", "old")
            try harness.editor.importMacrosCSV("việt,new")
            #expect(harness.editor.macroEntries.map(\.id) == [nfd])
            #expect(harness.editor.tables.replacement(for: "VIỆT") == "new")
            let word = harness.addExclusion("BÊN")
            try harness.editor.importExclusionsCSV("be\u{0302}n")
            #expect(harness.editor.exclusionEntries.map(\.id) == [word])
            #expect(harness.editor.tables.excludes("bên"))
        }
    }

    @Test func importSkipsIncompleteRowsWhenFindingTheWinner() throws {
        try withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let complete = harness.addMacro("vn", "A")
            let draft = harness.addMacro("vn", "")
            try harness.editor.importMacrosCSV("vn,C")
            #expect(harness.editor.macroEntries.map(\.id) == [complete, draft])
            #expect(harness.editor.macroEntries[0].replacement == "C")
            #expect(harness.editor.macroEntries[1].replacement == "")
        }
    }

    @Test func importAppliesRecordsInOrderSoTheLastRecordWins() throws {
        try withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            let existing = harness.addMacro("hn", "Hà Nội")
            try harness.editor.importMacrosCSV("vn,A\nsg,Sài Gòn\nVN,B")
            let entries = harness.editor.macroEntries
            #expect(entries.count == 3)
            #expect(entries[0].id == existing)
            #expect(entries.map(\.replacement) == ["Hà Nội", "B", "Sài Gòn"])
            #expect(typed("vn sg hn ", rules: harness.editor.tables) == "B Sài Gòn Hà Nội ")
            try harness.editor.importExclusionsCSV("been\ntest\nBEEN")
            #expect(harness.editor.exclusionEntries.map(\.word) == ["BEEN", "test"])
            #expect(harness.editor.tables.excludes("been"))
        }
    }

    @Test func exportedReplacementImportsWithTheSameScalars() throws {
        try withIsolatedDefaults { defaults in
            let replacement = " dòng 1, \"quote\"\n dòng 2 "
            let decomposed = "do\u{0300}ng\r\n"
            let source = Harness(defaults)
            source.addMacro("vn", replacement)
            source.addMacro("dg", decomposed)
            source.addMacro("", "draft")
            source.addExclusion("been")
            source.addExclusion("")
            let macros = source.editor.exportMacrosCSV()
            let exclusions = source.editor.exportExclusionsCSV()
            try withIsolatedDefaults { other in
                let target = Harness(other)
                try target.editor.importMacrosCSV(macros)
                try target.editor.importExclusionsCSV(exclusions)
                let entries = target.editor.macroEntries
                #expect(entries.map(\.trigger) == ["vn", "dg"])
                #expect(entries[0].replacement.unicodeScalars.elementsEqual(replacement.unicodeScalars))
                #expect(entries[1].replacement.unicodeScalars.elementsEqual(decomposed.unicodeScalars))
                #expect(target.editor.exclusionEntries.map(\.word) == ["been"])
                #expect(typed("vn ", rules: target.editor.tables) == replacement + " ")
                target.reload()
                #expect(target.editor.macroEntries[0].replacement.unicodeScalars.elementsEqual(replacement.unicodeScalars))
            }
        }
    }

    @Test func failedCSVImportPreservesExistingRules() {
        let malformedMacros = [
            "hn,Hà Nội\nsg,\"Sài Gòn",
            "hn,Hà Nội\nsg",
            "hn,Hà Nội\nsg,Sài Gòn,extra",
            "hn,Hà Nội\ns g,Sài Gòn",
            "hn,Hà Nội\n,Sài Gòn",
            "hn,Hà Nội\nsg,",
            "hn,Hà Nội\nsg,Sài\"Gòn",
            "",
        ]
        let malformedExclusions = [
            "code\n\"docker",
            "code\ndocker,admin",
            "code\ndoc ker",
            "code\n\"\"",
            "\n",
        ]
        for text in malformedMacros + malformedExclusions {
            withIsolatedDefaults { defaults in
                let harness = Harness(defaults)
                harness.addMacro("vn", "Việt Nam")
                harness.editor.addMacro()
                harness.addExclusion("been")
                harness.editor.addExclusion()
                let entries = (harness.editor.macroEntries, harness.editor.exclusionEntries)
                let exported = (harness.editor.exportMacrosCSV(), harness.editor.exportExclusionsCSV())
                let stored = (harness.storedRules, harness.storedExclusions)
                let tables = harness.editor.tables
                let count = harness.emitted.count
                if malformedMacros.contains(text) {
                    #expect(throws: (any Error).self) { try harness.editor.importMacrosCSV(text) }
                }
                if malformedExclusions.contains(text) {
                    #expect(throws: (any Error).self) { try harness.editor.importExclusionsCSV(text) }
                }
                #expect(harness.editor.macroEntries == entries.0)
                #expect(harness.editor.exclusionEntries == entries.1)
                #expect(harness.editor.exportMacrosCSV() == exported.0)
                #expect(harness.editor.exportExclusionsCSV() == exported.1)
                #expect(harness.storedRules == stored.0)
                #expect(harness.storedExclusions == stored.1)
                #expect(harness.editor.tables == tables)
                #expect(harness.emitted.count == count)
                #expect(typed("vn hn been ", rules: harness.editor.tables) == "Việt Nam hn been ")
                harness.reload()
                #expect(harness.editor.macroEntries == entries.0)
                #expect(harness.editor.exclusionEntries == entries.1)
                #expect(typed("vn hn ", rules: harness.editor.tables) == "Việt Nam hn ")
                #expect(!harness.editor.tables.excludes("code"))
            }
        }
    }

    @Test func exportWritesActiveRowsInOrder() {
        withIsolatedDefaults { defaults in
            let harness = Harness(defaults)
            harness.addMacro("vn", "A")
            harness.addMacro("hn", "")
            harness.addMacro("a,b", "say \"hi\"")
            harness.addMacro("VN", "B")
            harness.addExclusion("been")
            harness.addExclusion("")
            harness.addExclusion("te st")
            harness.addExclusion("test")
            #expect(harness.editor.exportMacrosCSV() == "vn,A\n\"a,b\",\"say \"\"hi\"\"\"\nVN,B")
            #expect(harness.editor.exportExclusionsCSV() == "been\ntest")
        }
    }
}
