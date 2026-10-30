import Testing
import DauKeyEngine
@testable import DauKeyHook

private func makeCore(
    enabled: Bool = true, options: Options = Options(), autoCapitalize: Bool = false, perAppSwitching: Bool = true,
    appMemory: [String: Bool] = [:], rules: RuleTables = RuleTables()
) -> TypingCore {
    TypingCore(
        enabled: enabled,
        settings: TypingSettings(
            options: options, session: SessionSettings(autoCapitalize: autoCapitalize), perAppSwitching: perAppSwitching
        ),
        appMemory: appMemory, rules: rules
    )
}

private func fresh() -> TypingCore { makeCore() }

private func key(_ character: Character, code: UInt16 = 0, _ modifiers: Modifiers = []) -> KeyInput {
    KeyInput(keyCode: code, modifiers: modifiers, characters: String(character))
}

private let backspaceKey = KeyInput(keyCode: 0x33, modifiers: [], characters: "")
private let escapeKey = KeyInput(keyCode: 0x35, modifiers: [], characters: "\u{1B}")
private let vietNam = RuleTables(macros: [MacroRule(trigger: "vn", replacement: "Việt Nam")])

private func expectScalars(_ actual: String, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(Array(actual.unicodeScalars) == Array(expected.unicodeScalars), "got \"\(actual)\"",
            sourceLocation: sourceLocation)
}

/// A field that shows typed text and a selected inline suggestion after the caret; the sender always succeeds.
private struct Screen {
    var text = ""
    var selectedSuggestion: String?
    private mutating func insert(_ value: String) {
        selectedSuggestion = nil
        text += value
    }
    private mutating func backspace(_ count: Int) {
        guard count > 0 else { return }
        let deletedSelection = selectedSuggestion != nil
        selectedSuggestion = nil
        text = String(text.dropLast(count - (deletedSelection ? 1 : 0)))
    }
    mutating func key(_ key: KeyInput, core: inout TypingCore) -> Decision {
        let result = core.keyDown(key)
        let steps: [OutputStep]
        let passes: Bool
        switch result.decision {
        case .pass: steps = []; passes = true
        case .swallow(let output): steps = output; passes = false
        case .passAfter(let output): steps = output; passes = true
        }
        for step in steps {
            switch step {
            case .backspaces(let n): backspace(n)
            case .selectBackward(let n):
                selectedSuggestion = nil
                text = String(text.dropLast(n))
            case .text(let value): insert(value)
            }
        }
        if result.requiresCommit { core.commitSent() }
        if passes {
            switch KeyClassifier.classify(key) {
            case .backspace: backspace(1)
            case .char: insert(key.characters)
            case .endWord, .reset: break
            }
        }
        return result.decision
    }
    mutating func type(_ string: String, core: inout TypingCore, suggesting: Bool = false) {
        for char in string {
            _ = key(KeyInput(keyCode: char == "<" ? 0x33 : 0,
                             modifiers: [], characters: char == "<" ? "" : String(char)), core: &core)
            if suggesting && char != " " { selectedSuggestion = "suggestion" }
        }
    }
}

/// A text field typed through the core the way the Typist drives it, and read the way the context reader does: two
/// reads per request published against one prior observation.
private struct Field {
    static let processID: Int32 = 7
    var core: TypingCore
    private(set) var text: String
    /// The selected range in UTF-16 units; length 0 is the caret.
    private(set) var selection: ContextSelection
    var element: UInt64 = 1
    private var prior: ContextSample?
    /// The latest request the core issued.
    private(set) var request: ContextRequest?

    init(_ core: TypingCore, app: String = "com.apple.TextEdit", inline: Bool = false, text: String = "") {
        self.core = core
        self.text = text
        selection = ContextSelection(location: text.utf16.count, length: 0)
        _ = self.core.appActivated(app, processID: Self.processID, inlineCompletionApp: inline)
        refresh()
    }

    /// Takes the core's next request, as the Typist does after every event, command and context result.
    mutating func refresh() {
        if let next = core.contextRequest() { request = next }
    }

    /// A key-down, its output, and its key-up. With `sendFails`, the sender stops after the first step.
    @discardableResult
    mutating func press(_ input: KeyInput, sendFails: Bool = false) -> RuntimeResult {
        let result = core.keyDown(input)
        let steps: [OutputStep]
        let passes: Bool
        switch result.decision {
        case .pass: steps = []; passes = true
        case .swallow(let output): steps = output; passes = false
        case .passAfter(let output): steps = output; passes = true
        }
        if sendFails, let first = steps.first {
            apply(first)
            core.sendFailed()
        } else {
            for step in steps { apply(step) }
            if result.requiresCommit { core.commitSent() }
        }
        if passes {
            switch KeyClassifier.classify(input) {
            case .char(let character): insert(String(character))
            case .backspace: deleteBackward()
            case .endWord, .reset: break
            }
        }
        refresh()
        _ = core.keyUp(input.keyCode)
        refresh()
        return result
    }

    /// Types each character with key code 0; `<` is Backspace.
    mutating func type(_ keys: String) {
        for character in keys { press(character == "<" ? backspaceKey : key(character)) }
    }

    /// The host changes the field by itself: a paste, an autocorrection, the user's selection.
    mutating func host(_ text: String, selecting selection: ContextSelection? = nil) {
        self.text = text
        self.selection = selection ?? ContextSelection(location: text.utf16.count, length: 0)
    }

    /// The host shows an inline suggestion after the caret, selected.
    mutating func suggest(_ suggestion: String) {
        let caret = selection.location
        text = String(text.utf16.prefix(caret))! + suggestion
        selection = ContextSelection(location: caret, length: suggestion.utf16.count)
    }

    func sample(text: String? = nil, selection: ContextSelection? = nil, ticket: ContextTicket? = nil) -> ContextSample {
        let text = text ?? self.text
        let selection = selection ?? self.selection
        return ContextSample(
            ticket: ticket ?? request!.ticket, target: ContextTarget(processID: Self.processID, elementID: element),
            selection: selection,
            context: TextContext(prefix: String(text.utf16.prefix(selection.location))!, startsAtDocumentStart: true),
            evidence: .unconfirmed
        )
    }

    /// The reader reads the field twice for the latest request, publishes the result, and the core judges it.
    @discardableResult
    mutating func read(before: ContextSample? = nil, after: ContextSample? = nil) -> AnchorEvidence? {
        let after = after ?? sample()
        guard let published = ContextEvidence.publish(
            before: before ?? after, after: after, expected: request?.expected, isLatest: true, priorActual: &prior
        ) else { return nil }
        core.handleContext(.sample(published))
        refresh()
        return published.evidence
    }

    mutating func unavailable() {
        core.handleContext(.unavailable(request!.ticket))
        refresh()
    }

    /// A physical event with no text, after which the Typist asks for a request.
    mutating func keyUp() {
        _ = core.keyUp(0x38)
        refresh()
    }

    private mutating func apply(_ step: OutputStep) {
        switch step {
        case .backspaces(let count): for _ in 0..<count { deleteBackward() }
        case .selectBackward(let count):
            var start = utf16Index(selection.location)
            for _ in 0..<count where start > text.startIndex { start = text.index(before: start) }
            let location = text.utf16.distance(from: text.startIndex, to: start)
            selection = ContextSelection(location: location, length: selection.location - location)
        case .text(let value): insert(value)
        }
    }

    private func utf16Index(_ offset: Int) -> String.Index {
        text.utf16.index(text.utf16.startIndex, offsetBy: offset)
    }

    private mutating func insert(_ value: String) {
        let start = utf16Index(selection.location)
        let end = utf16Index(selection.location + selection.length)
        text.replaceSubrange(start..<end, with: value)
        selection = ContextSelection(location: selection.location + value.utf16.count, length: 0)
    }

    private mutating func deleteBackward() {
        if selection.length > 0 {
            insert("")
            return
        }
        let end = utf16Index(selection.location)
        guard end > text.startIndex else { return }
        let start = text.index(before: end)
        let removed = text.utf16.distance(from: start, to: end)
        text.removeSubrange(start..<end)
        selection = ContextSelection(location: selection.location - removed, length: 0)
    }
}

@Suite struct TypingCoreTests {
    @Test func safariVNIReplacesSelectedInlineCompletionWithoutDuplicatingTheVowel() {
        let bundleID = "com.apple.Safari"
        let inlineCompletionApp = InlineCompletionApp.matches(bundleID: bundleID, exportedTypeIdentifiers: ["public.html"])
        var core = makeCore(options: Options(inputMethod: .vni))
        _ = core.appActivated(bundleID, processID: nil, inlineCompletionApp: inlineCompletionApp)
        var screen = Screen()
        screen.type("ta", core: &core)
        screen.selectedSuggestion = "ilscale.com"
        screen.type("81t", core: &core)
        expectScalars(screen.text, "tắt")
    }
    @Test func spotlightSequencesOverwriteSelectedSuggestions() {
        for (method, keys, expected) in [
            (InputMethod.vni, "tie6ng1 vie6t5 ", "tiếng việt "),
            (InputMethod.telex, "tieengs vieetj ", "tiếng việt "),
            (InputMethod.simpleTelex, "tieengs vieetj ", "tiếng việt "),
        ] {
            for inlineCompletionApp in [false, true] {
                var core = makeCore(options: Options(inputMethod: method))
                _ = core.appActivated("app.behind", processID: nil, inlineCompletionApp: inlineCompletionApp)
                core.keyTarget(isSpotlight: true)
                var screen = Screen()
                screen.type(keys, core: &core, suggesting: true)
                expectScalars(screen.text, expected)
            }
        }
    }
    @Test func spotlightTargetChangesStepsAndActivationResetsIt() {
        for bundleID in ["app.other", "com.emizuki.daukey", nil] {
            var core = fresh(), screen = Screen()
            _ = core.appActivated("com.google.Chrome", processID: nil, inlineCompletionApp: true)
            core.keyTarget(isSpotlight: true)
            screen.type("tie", core: &core)
            #expect(core.keyDown(key("e")).decision == .swallow([.selectBackward(1), .text("ê")]))
            _ = core.appActivated(bundleID, processID: nil, inlineCompletionApp: false)
            screen.type("tie", core: &core)
            let expected: [OutputStep] = bundleID == "com.emizuki.daukey"
                ? [.text("\u{202F}"), .backspaces(2), .text("ê")]
                : [.backspaces(1), .text("ê")]
            #expect(core.keyDown(key("e")).decision == .swallow(expected))
        }
    }
    @Test func spotlightTargetCanReturnToOrdinaryOutput() {
        var core = fresh(), screen = Screen()
        core.keyTarget(isSpotlight: true)
        core.keyTarget(isSpotlight: false)
        screen.type("tie", core: &core)
        #expect(core.keyDown(key("e")).decision == .swallow([.backspaces(1), .text("ê")]))
    }
    @Test func escapeFromSpotlightRestoresTheAppBehindOutput() {
        for inlineCompletionApp in [false, true] {
            var core = fresh(), screen = Screen()
            _ = core.appActivated("app.behind", processID: nil, inlineCompletionApp: inlineCompletionApp)
            core.keyTarget(isSpotlight: true)
            screen.type("tie", core: &core)
            #expect(screen.key(key("e"), core: &core) == .swallow([.selectBackward(1), .text("ê")]))
            #expect(core.keyDown(escapeKey).decision == .pass)
            core.keyTarget(isSpotlight: false)
            screen.type("tie", core: &core)
            let expected: [OutputStep] = inlineCompletionApp
                ? [.text("\u{202F}"), .backspaces(2), .text("ê")]
                : [.backspaces(1), .text("ê")]
            #expect(core.keyDown(key("e")).decision == .swallow(expected))
        }
    }
    @Test func inlineCompletionAppActivationAndOwnActivationPreservePlaceholder() {
        var core = fresh(), screen = Screen()
        _ = core.appActivated("com.google.Chrome", processID: nil, inlineCompletionApp: true)
        screen.type("tie", core: &core)
        #expect(core.keyDown(key("e")).decision == .swallow([.text("\u{202F}"), .backspaces(2), .text("ê")]))
        _ = core.appActivated("com.emizuki.daukey", processID: nil, inlineCompletionApp: false)
        screen.type("tie", core: &core)
        #expect(core.keyDown(key("e")).decision == .swallow([.text("\u{202F}"), .backspaces(2), .text("ê")]))
        _ = core.appActivated(nil, processID: nil, inlineCompletionApp: true)
        screen.type("tie", core: &core)
        #expect(core.keyDown(key("e")).decision == .swallow([.backspaces(1), .text("ê")]))
    }
    @Test func inlineCompletionVNISequenceLeavesCorrectScreen() {
        var core = makeCore(options: Options(inputMethod: .vni))
        _ = core.appActivated("com.google.Chrome", processID: nil, inlineCompletionApp: true)
        var screen = Screen()
        screen.type("Tie6ng1 ", core: &core)
        expectScalars(screen.text, "Tiếng ")
    }
    @Test func inlineCompletionSequencesReplaceSelectedSuggestionsWithoutLeavingPlaceholder() {
        for (method, keys, expected) in [
            (InputMethod.vni, "Tie6ng1 Vie6t5 ", "Tiếng Việt "),
            (InputMethod.telex, "tieengs ", "tiếng "),
            (InputMethod.simpleTelex, "tieengs ", "tiếng "),
        ] {
            for suggesting in [false, true] {
                var core = makeCore(options: Options(inputMethod: method))
                _ = core.appActivated("com.google.Chrome", processID: nil, inlineCompletionApp: true)
                var screen = Screen()
                screen.type(keys, core: &core, suggesting: suggesting)
                expectScalars(screen.text, expected)
                #expect(!screen.text.contains("\u{202F}"))
                #expect(screen.selectedSuggestion == nil)
            }
        }
    }
    @Test func selectedSuggestionConsumesFirstBackspaceWithoutInlineCompletionWorkaround() {
        var core = makeCore(options: Options(inputMethod: .vni))
        _ = core.appActivated("com.google.Chrome", processID: nil, inlineCompletionApp: false)
        var screen = Screen()
        screen.type("Tie6", core: &core, suggesting: true)
        expectScalars(screen.text, "Tieê")
        screen.type("ng1 Vie6t5 ", core: &core, suggesting: true)
        #expect(screen.text != "Tiếng Việt ")
        #expect(!screen.text.contains("\u{202F}"))
    }
    @Test func composesReopensAndRestoresBeforeOriginalBreak() {
        var core = fresh(), screen = Screen()
        screen.type("tieengs ", core: &core)
        expectScalars(screen.text, "tiếng ")
        screen.type("<f", core: &core)
        expectScalars(screen.text, "tiềng")
        core.reset()
        screen = Screen()
        screen.type("text", core: &core)
        #expect(screen.key(key(" "), core: &core) == .passAfter([.backspaces(2), .text("ext")]))
        expectScalars(screen.text, "text ")
    }
    @Test func everyResetBoundaryStartsFresh() {
        let resetters: [(inout TypingCore) -> Void] = [
            { $0.mouseDown() }, { $0.inputSourceChanged() }, { $0.reset() },
            { _ = $0.appActivated("app.b", processID: nil, inlineCompletionApp: false) },
            { _ = $0.appActivated("com.emizuki.daukey", processID: nil, inlineCompletionApp: false) },
            { _ = $0.appActivated(nil, processID: nil, inlineCompletionApp: false) }, { _ = $0.setEnabled(true) },
        ]
        for reset in resetters {
            var core = fresh(), screen = Screen()
            screen.type("to", core: &core)
            reset(&core)
            screen.type("s", core: &core)
            expectScalars(screen.text, "tos")
        }
    }
    @Test func toggleMidWordAndDisabledKeysPass() {
        var core = fresh(), screen = Screen()
        screen.type("to", core: &core)
        #expect(!core.flagsChanged([.control, .shift]).modeChanged)
        #expect(core.flagsChanged([]).modeChanged)
        #expect(!core.snapshot.enabled)
        screen.type("is", core: &core)
        expectScalars(screen.text, "tois")
        _ = core.flagsChanged([.control, .shift])
        #expect(core.flagsChanged([]).modeChanged)
        screen.type("as", core: &core)
        expectScalars(screen.text, "toisá")
    }
    @Test func shortcutsReturnAndModifiedDeleteCannotReopen() {
        for key in [KeyInput(keyCode: 9, modifiers: .command, characters: "v"),
                    KeyInput(keyCode: 0x24, modifiers: .shift, characters: "\n"),
                    KeyInput(keyCode: 0x33, modifiers: .option, characters: "")] {
            var core = fresh(), screen = Screen()
            screen.type("toi ", core: &core)
            _ = screen.key(key, core: &core)
            screen.type("<s", core: &core)
            expectScalars(screen.text, key.keyCode == 0x24 ? "toi s" : "tois")
        }
        var core = fresh(), screen = Screen()
        screen.type("toi", core: &core)
        let paste = KeyInput(keyCode: 9, modifiers: .command, characters: "v")
        #expect(screen.key(paste, core: &core) == .pass)
        #expect(screen.key(backspaceKey, core: &core) == .pass)
        expectScalars(screen.text, "to")
        screen.type("s", core: &core)
        expectScalars(screen.text, "tos")
    }
    @Test func backspaceCanInsertReplacementText() {
        var core = fresh(), screen = Screen()
        screen.type("siste", core: &core)
        expectScalars(screen.text, "sité")
        #expect(screen.key(backspaceKey, core: &core) == .swallow([.backspaces(3), .text("ít")]))
        expectScalars(screen.text, "sít")
    }
    @Test func memoryOwnActivationAndSnapshotChanges() {
        var core = fresh(), screen = Screen()
        let initial = core.snapshot
        screen.type("tieengs", core: &core)
        #expect(core.snapshot == initial)
        _ = core.appActivated("app.a", processID: nil, inlineCompletionApp: false)
        _ = core.setEnabled(false)
        let beforeOwn = core.snapshot
        _ = core.appActivated("com.emizuki.daukey", processID: nil, inlineCompletionApp: false)
        #expect(core.snapshot == beforeOwn)
        _ = core.setEnabled(true)
        #expect(core.snapshot.appMemory["app.a"] == true)
        _ = core.appActivated("app.b", processID: nil, inlineCompletionApp: false)
        _ = core.setEnabled(false)
        _ = core.appActivated("app.a", processID: nil, inlineCompletionApp: false)
        #expect(core.snapshot.enabled)
        #expect(core.snapshot.appMemory == ["app.a": true, "app.b": false])
        _ = core.appActivated(nil, processID: nil, inlineCompletionApp: false)
        _ = core.setEnabled(false)
        #expect(core.snapshot.appMemory["app.a"] == true)
        let beforeToggle = core.snapshot
        _ = core.flagsChanged([.control, .shift])
        #expect(core.flagsChanged([]).modeChanged)
        #expect(core.snapshot != beforeToggle)
        core.setTap(.unavailable)
        #expect(core.snapshot.tap == .unavailable)
    }
    /// Settings changes apply to the next word and are not hook resets, so they no longer disturb the chord.
    @Test func eachDisturbanceSpoilsArmedChordEvenWhenDisabled() {
        let disturbances: [(inout TypingCore) -> Void] = [
            { _ = $0.keyDown(KeyInput(keyCode: 0, modifiers: .control, characters: "a")) },
            { $0.mouseDown() }, { $0.reset() }, { _ = $0.appActivated(nil, processID: nil, inlineCompletionApp: false) },
            { $0.inputSourceChanged() }, { _ = $0.setEnabled(false) },
        ]
        for disturb in disturbances {
            var core = makeCore(enabled: false)
            _ = core.flagsChanged([.control, .shift])
            disturb(&core)
            #expect(!core.flagsChanged([]).modeChanged)
            #expect(!core.snapshot.enabled)
        }
    }
    @Test func emojiAndNonLatinBreaksDoNotCorruptNextWord() {
        var core = fresh(), screen = Screen()
        screen.type("xin👩‍💻дchaof", core: &core)
        expectScalars(screen.text, "xin👩‍💻дchào")
    }
    @Test func perAppSwitchingDisabledPreservesStateAcrossApps() {
        var core = makeCore(perAppSwitching: false)
        #expect(core.snapshot.enabled == true)
        _ = core.appActivated("app.a", processID: nil, inlineCompletionApp: false)
        _ = core.setEnabled(false)
        #expect(core.snapshot.enabled == false)
        _ = core.appActivated("app.b", processID: nil, inlineCompletionApp: false)
        #expect(core.snapshot.enabled == false)
        _ = core.appActivated("app.a", processID: nil, inlineCompletionApp: false)
        #expect(core.snapshot.enabled == false)
    }
    /// A word typed at a known sentence start is capitalized; a later word in the sentence is not, even after a
    /// Backspace empties it.
    @Test func midSentenceBackspaceDoesNotCapitalize() {
        var field = Field(makeCore(autoCapitalize: true))
        field.read()
        field.type("c b<b")
        expectScalars(field.text, "C b")
    }
    @Test func typedCaseAndKnownSentenceStartCapitalize() {
        var plain = Field(makeCore())
        plain.read()
        plain.type("Tooi")
        expectScalars(plain.text, "Tôi")
        for keys in ["Tooi", "tooi"] {
            var field = Field(makeCore(autoCapitalize: true))
            field.read()
            field.type(keys)
            expectScalars(field.text, "Tôi")
        }
        var unknown = Field(makeCore(autoCapitalize: true))
        unknown.type("tooi")
        expectScalars(unknown.text, "tôi")
    }
}

/// The contracts of the runtime core: settings, shortcuts, capture, output receipts, and host context.
@Suite struct TypingCoreRuntimeTests {
    @Test func settingsIntentsChangeOnlyTheirField() {
        var core = fresh()
        let changes: [SettingsChange] = [
            .inputMethod(.vni), .spelling(.off), .toneStyle(.modern), .allowForeignConsonants(true),
            .autoCapitalize(true), .soundEnabled(true), .perAppSwitching(false),
            .shortcut(ShortcutConfig(modifiers: [.control], keyCode: 0x06)),
        ]
        for change in changes {
            let result = core.apply(change)
            #expect(!result.modeChanged)
        }
        #expect(core.snapshot.settings == TypingSettings(
            options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .off, allowForeignConsonants: true),
            session: SessionSettings(autoCapitalize: true),
            shortcut: ShortcutConfig(modifiers: [.control], keyCode: 0x06), perAppSwitching: false, soundEnabled: true
        ))
        #expect(core.snapshot.enabled)
    }

    @Test func settingsAndRulesMidWordDoNotResetTheWord() {
        var field = Field(fresh())
        field.type("to")
        _ = field.core.apply(.inputMethod(.vni))
        field.core.replaceRules(vietNam)
        field.refresh()
        field.type("s to6i vn ")
        expectScalars(field.text, "tó tôi Việt Nam ")
    }

    @Test func outputAcknowledgementControlsContext() {
        // The receipt for textual output holds the next read until the sender is done.
        var core = fresh()
        _ = core.appActivated("app", processID: Field.processID, inlineCompletionApp: false)
        let first = core.contextRequest()
        #expect(first != nil)
        let typed = core.keyDown(key("t"))
        #expect(typed.decision == .pass && typed.requiresCommit)
        let pinned = core.contextRequest()
        #expect(pinned == nil)
        core.commitSent()
        let released = core.contextRequest()
        #expect(released?.expected == nil)
        #expect(released != nil)
        // Key-ups, flags and Escape have no text effect and open no receipt.
        _ = core.apply(.shortcut(ShortcutConfig(modifiers: [.control], keyCode: 0x06)))
        let events: [(inout TypingCore) -> RuntimeResult] = [
            { $0.keyUp(0) }, { $0.flagsChanged([.shift]) }, { $0.keyDown(escapeKey) },
        ]
        for event in events {
            let result = event(&core)
            #expect(result.decision == .pass && !result.requiresCommit)
            let request = core.contextRequest()
            #expect(request != nil)
        }

        // While V/E is off nothing is read: neither after physical events nor after commands.
        let shortcut = KeyInput(keyCode: 0x06, modifiers: .control, characters: "z")
        let off = core.keyDown(shortcut)
        #expect(off.decision == .swallow([]) && !off.requiresCommit && off.modeChanged)
        let disabled: [(inout TypingCore) -> Void] = [
            { _ = $0.keyUp(0x06) }, { _ = $0.keyDown(key("a")) }, { _ = $0.keyUp(0) }, { _ = $0.flagsChanged([]) },
            { $0.mouseDown() }, { _ = $0.appActivated("app.b", processID: 8, inlineCompletionApp: false) },
            { _ = $0.apply(.soundEnabled(true)) }, { $0.replaceRules(vietNam) }, { $0.reset() },
            { $0.inputSourceChanged() },
        ]
        for event in disabled {
            let none = core.contextRequest()
            #expect(none == nil)
            event(&core)
            let request = core.contextRequest()
            #expect(request == nil)
        }
        // Turning V/E back on reads again at once and after the next physical event.
        let on = core.keyDown(shortcut)
        #expect(on.modeChanged)
        let reenabled = core.contextRequest()
        #expect(reenabled?.ticket.processID == 8)
        _ = core.keyUp(0x06)
        let next = core.contextRequest()
        #expect(next != nil)
        _ = core.setEnabled(false)
        let offAgain = core.contextRequest()
        #expect(offAgain == nil)
        _ = core.setEnabled(true)
        let byCommand = core.contextRequest()
        #expect(byCommand != nil)

        // A pass without text does not wait for the host: with no expectation, a settled read anchors.
        var quiet = Field(fresh())
        quiet.read()
        quiet.unavailable()
        quiet.keyUp()
        quiet.read()
        quiet.keyUp()
        #expect(quiet.request?.expected != nil)

        // While output waits for the host, a read that matches the expectation fully anchors and keeps the word.
        var matching = Field(fresh())
        matching.read()
        matching.type("toi")
        #expect(matching.read() == .transitionConfirmed)
        matching.keyUp()
        #expect(matching.request?.expected?.selection == ContextSelection(location: 3, length: 0))
        matching.type("s")
        expectScalars(matching.text, "tói")

        // A read from before the last key lags behind the output and is ignored; the word stays.
        var lagging = Field(fresh())
        lagging.read()
        lagging.type("toi")
        lagging.read(after: lagging.sample(text: "to", selection: ContextSelection(location: 2, length: 0)))
        lagging.type("s")
        expectScalars(lagging.text, "tói")

        // A send that fails part way drops ownership: nothing is deleted from what the host shows.
        var failing = Field(fresh())
        failing.read()
        failing.type("toi")
        failing.read()
        let failed = failing.press(key("s"), sendFails: true)
        #expect(failed.decision == .swallow([.backspaces(2), .text("ói")]))
        #expect(failing.request?.expected == nil)
        // The host may still show the text from before the partial output: a settled read is no anchor.
        #expect(failing.read(after: failing.sample(text: "toi", selection: ContextSelection(location: 3, length: 0)))
                == .settled)
        failing.keyUp()
        #expect(failing.request?.expected == nil)
        #expect(failing.read() == .transitionConfirmed)
        failing.keyUp()
        #expect(failing.request?.expected != nil)
        let retyped = failing.press(key("s"))
        #expect(retyped.decision == .pass)
        expectScalars(failing.text, "ts")
    }

    @Test func contextAcceptancePreservesOrDropsOwnership() {
        // Stale, unconfirmed and lagging reads change nothing while the output waits for the host.
        var waiting = Field(fresh())
        waiting.read()
        waiting.type("toi")
        let stale = waiting.request!.ticket
        waiting.type(".")
        waiting.read(after: waiting.sample(ticket: stale))
        waiting.read(before: waiting.sample(text: "toi", selection: ContextSelection(location: 3, length: 0)))
        #expect(waiting.read(after: waiting.sample(text: "toi", selection: ContextSelection(location: 3, length: 0)))
                == .transitionConfirmed)
        waiting.type("<s")
        expectScalars(waiting.text, "tói")

        // Once anchored, a confirmed change of the owned text drops the word and its reopen frame.
        var corrected = Field(fresh())
        corrected.read()
        corrected.type("toi.")
        #expect(corrected.read() == .transitionConfirmed)
        corrected.host("tai.")
        #expect(corrected.read() == .transitionConfirmed)
        #expect(corrected.request?.expected == nil)
        corrected.type("<s")
        expectScalars(corrected.text, "tais")

        // An unreadable context keeps composing from what the session typed itself.
        var unreadable = Field(fresh())
        unreadable.read()
        unreadable.type("toi.")
        unreadable.unavailable()
        unreadable.type("<s")
        expectScalars(unreadable.text, "tói")
    }

    @Test func focusInvalidationIsAFactForTheCurrentProcess() {
        // An invalidation carries the ticket of the read that saw the move, which may be older than the current one.
        var moved = Field(fresh())
        moved.read()
        moved.type("toi")
        let older = moved.request!.ticket
        moved.type(".")
        moved.core.handleContext(.invalidated(older))
        moved.refresh()
        #expect(moved.request?.expected == nil)
        moved.type("<s")
        expectScalars(moved.text, "tois")

        // Another process's focus is not this app's.
        var other = Field(fresh())
        other.read()
        other.type("toi.")
        other.core.handleContext(.invalidated(ContextTicket(generation: 0, watermark: 0, processID: 99)))
        other.type("<s")
        expectScalars(other.text, "tói")

        // The invalidation keeps waiting for output the host has not shown: a settled read stays ignored.
        var pending = Field(fresh())
        pending.read()
        pending.type("toi")
        pending.read()
        pending.type("s")
        let lag = pending.sample(text: "toi", selection: ContextSelection(location: 3, length: 0))
        #expect(pending.read(after: lag) == .settled)
        pending.core.handleContext(.invalidated(pending.request!.ticket))
        pending.refresh()
        #expect(pending.read(after: lag) == .settled)
        pending.keyUp()
        #expect(pending.request?.expected == nil)
        // Only the text changed, which is no evidence without an expectation; the newly focused element is.
        #expect(pending.read() == .settled)
        pending.keyUp()
        #expect(pending.request?.expected == nil)
        pending.element = 2
        #expect(pending.read() == .transitionConfirmed)
        pending.keyUp()
        #expect(pending.request?.expected != nil)
    }

    @Test func reanchoredUserSelectionCannotDeleteHostPrefix() {
        for (app, inline) in [("com.apple.TextEdit", false), ("com.apple.Safari", true)] {
            var field = Field(fresh(), app: app, inline: inline)
            field.read()
            field.type("toi")
            if inline {
                // In an app with inline suggestions, the user selects through the hook, which drops ownership.
                field.press(KeyInput(keyCode: 0x7C, modifiers: [.shift, .function], characters: ""))
            } else {
                field.unavailable()
            }
            field.host("toiXYZ tail", selecting: ContextSelection(location: 3, length: 3))
            #expect(field.read() == .transitionConfirmed)
            field.type("s")
            expectScalars(field.text, "tois tail")
        }
    }

    @Test func inlineSuggestionSamplesPreserveComposition() {
        var vni = Field(makeCore(options: Options(inputMethod: .vni)), app: "com.apple.Safari", inline: true)
        vni.read()
        vni.type("t")
        vni.read()
        vni.type("a")
        vni.suggest("ilscale.com")
        #expect(vni.read() == .transitionConfirmed)
        vni.type("8")
        vni.read()
        vni.suggest("m")
        vni.read()
        vni.type("1t")
        expectScalars(vni.text, "tắt")

        var telex = Field(fresh(), app: "com.apple.Safari", inline: true)
        telex.read()
        telex.type("t")
        telex.suggest("est")
        telex.read()
        telex.type("i")
        telex.read()
        telex.type("e")
        telex.suggest("ngine")
        telex.read()
        let erase = telex.press(backspaceKey)
        #expect(erase.decision == .pass && erase.requiresCommit)
        expectScalars(telex.text, "tie")
        telex.type("e")
        telex.suggest("x")
        telex.read()
        telex.type("ngs ")
        expectScalars(telex.text, "tiếng ")

        // Outside the exception the same selection is not a suggestion: the word goes, nothing is deleted.
        for (app, inline, location, prefix) in [
            ("com.apple.TextEdit", false, 2, "ta"), ("com.apple.Safari", true, 1, "ta"),
            ("com.apple.Safari", true, 2, "tx"),
        ] {
            var field = Field(makeCore(options: Options(inputMethod: .vni)), app: app, inline: inline)
            field.read()
            field.type("ta")
            field.read()
            field.host(prefix + "ilscale.com", selecting: ContextSelection(location: location, length: 11))
            field.read()
            #expect(field.request?.expected == nil, "\(app) at \(location) after \(prefix)")
        }
    }

    @Test func selectionReplacementMovesTheCaretByInsertedUnits() {
        var field = Field(fresh(), text: "0123456789abcde")
        field.host("0123456789abcde", selecting: ContextSelection(location: 10, length: 5))
        field.read()
        field.press(key("X"))
        expectScalars(field.text, "0123456789X")
        #expect(field.request?.expected?.selection == ContextSelection(location: 11, length: 0))
        #expect(field.request?.expected?.context == TextContext(prefix: "0123456789X", startsAtDocumentStart: true))
    }

    @Test func knownHostMacroThroughAcceptedContext() {
        var joined = Field(makeCore(rules: vietNam), text: "a.")
        #expect(joined.read() == .settled)
        joined.type("vn vn ")
        expectScalars(joined.text, "a.vn Việt Nam ")

        var spaced = Field(makeCore(rules: vietNam), text: "a. ")
        spaced.read()
        spaced.type("vn ")
        expectScalars(spaced.text, "a. Việt Nam ")
    }

    @Test func shiftedDelimitersBypassOneMacroEvent() {
        var space = Field(makeCore(rules: vietNam))
        space.type("vn")
        #expect(space.press(KeyInput(keyCode: 0x31, modifiers: .shift, characters: " ")).decision == .pass)
        expectScalars(space.text, "vn ")
        space.type("< ")
        expectScalars(space.text, "Việt Nam ")

        for code: UInt16 in [0x24, 0x4C] {
            var field = Field(makeCore(rules: vietNam))
            field.type("vn")
            #expect(field.press(KeyInput(keyCode: code, modifiers: .shift, characters: "\r")).decision == .pass)
            expectScalars(field.text, "vn\n")
            field.type("< ")
            expectScalars(field.text, "vn ")
        }

        var enter = Field(makeCore(rules: vietNam))
        enter.type("vn")
        #expect(enter.press(KeyInput(keyCode: 0x24, modifiers: [], characters: "\r")).decision
                == .passAfter([.backspaces(2), .text("Việt Nam")]))
        expectScalars(enter.text, "Việt Nam\n")

        var bang = Field(makeCore(rules: vietNam))
        bang.type("vn")
        bang.press(KeyInput(keyCode: 0x12, modifiers: .shift, characters: "!"))
        expectScalars(bang.text, "Việt Nam!")
    }

    @Test func unknownEffectShortcutDropsSentenceContext() {
        var control = Field(makeCore(autoCapitalize: true), text: "Xin chào. ")
        control.read()
        control.type("toi")
        expectScalars(control.text, "Xin chào. Toi")

        let shortcuts = [
            KeyInput(keyCode: 0x09, modifiers: .command, characters: "v"),
            KeyInput(keyCode: 0x07, modifiers: .command, characters: "x"),
            KeyInput(keyCode: 0x06, modifiers: .command, characters: "z"),
            KeyInput(keyCode: 0x00, modifiers: .command, characters: "a"),
            KeyInput(keyCode: 0x7B, modifiers: .function, characters: ""),
            KeyInput(keyCode: 0x73, modifiers: .function, characters: ""),
            KeyInput(keyCode: 0x75, modifiers: .function, characters: ""),
            KeyInput(keyCode: 0x33, modifiers: .option, characters: ""),
        ]
        for shortcut in shortcuts {
            var field = Field(makeCore(autoCapitalize: true), text: "Xin chào. ")
            field.read()
            let ticket = field.request!.ticket
            let result = field.press(shortcut)
            #expect(result.decision == .pass && !result.requiresCommit && !result.modeChanged)
            #expect(field.request!.ticket.generation > ticket.generation)
            #expect(field.request?.expected == nil)
            let paste = shortcut.keyCode == 0x09
            if paste { field.host("Xin chào. abc") }
            field.type("toi")
            expectScalars(field.text, paste ? "Xin chào. abctoi" : "Xin chào. toi")
        }

        // Escape ends the word only; the caret did not move.
        var escape = Field(makeCore(autoCapitalize: true), text: "Xin chào. ")
        escape.read()
        escape.type("to")
        let ticket = escape.request!.ticket
        #expect(!escape.press(escapeKey).requiresCommit)
        #expect(escape.request!.ticket.generation == ticket.generation)
        #expect(escape.request?.expected != nil)

        // Return and Tab keep their own side effects: the original key goes through.
        for code: UInt16 in [0x24, 0x30] {
            var field = Field(fresh())
            field.type("to")
            let result = field.press(KeyInput(keyCode: code, modifiers: [], characters: code == 0x24 ? "\r" : "\t"))
            #expect(result.decision == .pass && result.requiresCommit)
            expectScalars(field.text, code == 0x24 ? "to\n" : "to\t")
        }
    }

    @Test func contextRefreshFollowsPhysicalEventsAndCommands() {
        var core = fresh()
        _ = core.appActivated("app.a", processID: 7, inlineCompletionApp: false)
        let events: [(inout TypingCore) -> Void] = [
            { _ = $0.keyUp(0) }, { _ = $0.flagsChanged([.shift]) }, { _ = $0.flagsChanged([]) }, { $0.mouseDown() },
            { _ = $0.appActivated("app.b", processID: 8, inlineCompletionApp: false) }, { $0.reset() },
            { $0.inputSourceChanged() }, { _ = $0.setEnabled(true) }, { _ = $0.resetToDefaults() },
        ]
        let first = core.contextRequest()
        #expect(first != nil)
        for event in events {
            let none = core.contextRequest()
            #expect(none == nil)
            event(&core)
            let next = core.contextRequest()
            #expect(next != nil)
        }
        // A result for the current ticket does not issue another read of it.
        _ = core.keyUp(0)
        let request = core.contextRequest()!
        core.handleContext(.sample(ContextSample(
            ticket: request.ticket, target: ContextTarget(processID: 8, elementID: 1),
            selection: ContextSelection(location: 0, length: 0),
            context: TextContext(prefix: "", startsAtDocumentStart: true), evidence: .settled
        )))
        let afterSample = core.contextRequest()
        #expect(afterSample == nil)
        core.handleContext(.unavailable(request.ticket))
        let afterUnavailable = core.contextRequest()
        #expect(afterUnavailable == nil)
    }

    @Test func modeChangedOnlyWhenEnabledChanges() {
        var core = fresh()
        var changes: [Bool] = []
        changes.append(core.setEnabled(true).modeChanged)
        changes.append(core.setEnabled(false).modeChanged)
        changes.append(core.apply(.enabled(false)).modeChanged)
        changes.append(core.apply(.enabled(true)).modeChanged)
        #expect(changes == [false, true, false, true])

        changes = []
        changes.append(core.appActivated("app.a", processID: 1, inlineCompletionApp: false).modeChanged)
        _ = core.setEnabled(false)
        changes.append(core.appActivated("app.b", processID: 2, inlineCompletionApp: false).modeChanged)
        _ = core.setEnabled(true)
        changes.append(core.appActivated("app.a", processID: 1, inlineCompletionApp: false).modeChanged)
        changes.append(core.appActivated("app.a", processID: 1, inlineCompletionApp: false).modeChanged)
        changes.append(core.resetToDefaults().modeChanged)
        changes.append(core.resetToDefaults().modeChanged)
        #expect(changes == [false, false, true, false, true, false])

        _ = core.flagsChanged([.control, .shift])
        #expect(core.flagsChanged([]).modeChanged)
    }

    /// A modifier+key shortcut toggles at its first key-down; its repeats and key-up are swallowed without toggling.
    @Test func modifierKeyShortcutTogglesOnceAndSwallowsItsRepeatsAndKeyUp() {
        var core = fresh()
        _ = core.apply(.shortcut(ShortcutConfig(modifiers: [.control], keyCode: 0x06)))
        let press = KeyInput(keyCode: 0x06, modifiers: .control, characters: "z")
        let repeated = KeyInput(keyCode: 0x06, modifiers: .control, characters: "z", isRepeat: true)
        let results = [core.keyDown(press), core.keyDown(repeated), core.keyUp(0x06), core.keyUp(0x06)]
        #expect(results.map(\.decision) == [.swallow([]), .swallow([]), .swallow([]), .pass])
        #expect(results.map(\.modeChanged) == [true, false, false, false])
        #expect(!core.snapshot.enabled)
        #expect(core.keyDown(press).modeChanged)
        #expect(core.snapshot.enabled)
    }

    @Test func activeCapturePassesInputWithoutComposing() {
        var field = Field(fresh())
        field.read()
        let before = field.core.snapshot
        field.core.beginShortcutCapture(id: 1)
        #expect(field.core.snapshot.shortcutCapture == CaptureSnapshot(id: 1, phase: .recording))
        for character in "tieengs" {
            let result = field.press(key(character))
            #expect(result.decision == .pass && !result.requiresCommit && !result.modeChanged)
        }
        expectScalars(field.text, "tieengs")
        #expect(!field.core.flagsChanged([.control, .shift]).modeChanged)
        #expect(!field.core.flagsChanged([]).modeChanged)
        let recorded = CaptureSnapshot(id: 1, phase: .recorded(ShortcutConfig(modifiers: [.control, .shift])))
        #expect(field.core.snapshot.shortcutCapture == recorded)
        field.press(key("a"))
        #expect(field.core.snapshot.shortcutCapture == recorded)
        #expect(field.core.snapshot.enabled == before.enabled)
        #expect(field.core.snapshot.appMemory == before.appMemory)
        #expect(field.core.snapshot.settings == before.settings)
        field.core.endShortcutCapture(id: 1)
        #expect(field.core.snapshot.shortcutCapture == CaptureSnapshot(id: 1, phase: .inactive))
        field.type(" aa")
        expectScalars(field.text, "tieengsa â")
    }

    @Test func captureCancellationResumesTypingBeforeShortcutRearm() {
        // Cancelled while Shift is held: typing composes at once.
        var field = Field(fresh())
        _ = field.core.flagsChanged([.shift])
        field.core.beginShortcutCapture(id: 1)
        #expect(field.core.snapshot.shortcutCapture == CaptureSnapshot(id: 1, phase: .waitingForRelease))
        field.core.endShortcutCapture(id: 1)
        #expect(field.core.snapshot.shortcutCapture == CaptureSnapshot(id: 1, phase: .inactive))
        field.press(KeyInput(keyCode: 0x11, modifiers: .shift, characters: "T"))
        field.type("oo")
        expectScalars(field.text, "Tô")
        var toggles: [Bool] = []
        toggles.append(field.core.flagsChanged([]).modeChanged)

        // Cancelled while the chord is held: its release does not toggle, a clean chord does.
        _ = field.core.flagsChanged([.control, .shift])
        field.core.beginShortcutCapture(id: 2)
        field.core.endShortcutCapture(id: 2)
        toggles.append(field.core.flagsChanged([.control]).modeChanged)
        toggles.append(field.core.flagsChanged([]).modeChanged)
        #expect(field.core.snapshot.enabled)
        _ = field.core.flagsChanged([.control, .shift])
        toggles.append(field.core.flagsChanged([]).modeChanged)
        #expect(toggles == [false, false, false, true])
        #expect(!field.core.snapshot.enabled)

        // Ending another capture changes nothing.
        field.core.beginShortcutCapture(id: 3)
        field.core.endShortcutCapture(id: 2)
        #expect(field.core.snapshot.shortcutCapture == CaptureSnapshot(id: 3, phase: .recording))
    }

    @Test func resetRetainsExternalTargetWithoutRepopulatingMemory() {
        for viaSettings in [false, true] {
            var core = fresh()
            func setEnabled(_ value: Bool) {
                _ = viaSettings ? core.apply(.enabled(value)) : core.setEnabled(value)
            }
            _ = core.appActivated("com.apple.Notes", processID: 10, inlineCompletionApp: false)
            setEnabled(true)
            #expect(core.snapshot.appMemory == ["com.apple.Notes": true])
            // Reset from the context menu: DauKey is not activated.
            _ = core.resetToDefaults()
            #expect(core.snapshot.appMemory.isEmpty)
            setEnabled(false)
            _ = core.appActivated("com.apple.Safari", processID: 11, inlineCompletionApp: true)
            setEnabled(true)
            _ = core.appActivated("com.apple.Notes", processID: 10, inlineCompletionApp: false)
            #expect(!core.snapshot.enabled)
            #expect(core.snapshot.appMemory == ["com.apple.Notes": false, "com.apple.Safari": true])
        }
        // Turning per-app switching back on during the reset records no entry for the current app.
        var off = makeCore(perAppSwitching: false)
        _ = off.appActivated("com.apple.Notes", processID: 10, inlineCompletionApp: false)
        _ = off.resetToDefaults()
        #expect(off.snapshot.appMemory.isEmpty)
        #expect(off.snapshot.settings == TypingSettings())
        #expect(off.snapshot.enabled)
    }
}
