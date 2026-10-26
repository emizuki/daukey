import Testing
import DauKeyEngine
@testable import DauKeyHook

private struct Screen {
    var text = ""
    mutating func key(_ key: KeyInput, core: inout TypingCore) -> Decision {
        let decision = core.keyDown(key)
        let steps: [OutputStep]
        let passes: Bool
        switch decision {
        case .pass: steps = []; passes = true
        case .swallow(let output): steps = output; passes = false
        case .passAfter(let output): steps = output; passes = true
        }
        for step in steps {
            switch step {
            case .backspaces(let n): text = String(text.dropLast(n))
            case .text(let value): text += value
            }
        }
        if passes {
            switch KeyClassifier.classify(key) {
            case .backspace: text = String(text.dropLast())
            case .char: text += key.characters
            case .endWord, .reset: break
            }
        }
        return decision
    }
    mutating func type(_ string: String, core: inout TypingCore) {
        for char in string {
            _ = key(KeyInput(keyCode: char == "<" ? 0x33 : 0,
                             modifiers: [], characters: char == "<" ? "" : String(char)), core: &core)
        }
    }
}
private func fresh() -> TypingCore {
    TypingCore(enabled: true, options: Options(), appMemory: [:])
}
private func expectScalars(_ actual: String, _ expected: String) {
    #expect(Array(actual.unicodeScalars) == Array(expected.unicodeScalars))
}

@Suite struct TypingCoreTests {
    @Test func chromiumActivationAndOwnActivationPreservePlaceholder() {
        var core = fresh(), screen = Screen()
        core.appActivated("com.google.Chrome", chromiumBrowser: true)
        screen.type("tie", core: &core)
        #expect(core.keyDown(KeyInput(keyCode: 0, modifiers: [], characters: "e"))
                == .swallow([.text("\u{202F}"), .backspaces(2), .text("ê")]))
        core.appActivated("com.emizuki.daukey", chromiumBrowser: false)
        screen.type("tie", core: &core)
        #expect(core.keyDown(KeyInput(keyCode: 0, modifiers: [], characters: "e"))
                == .swallow([.text("\u{202F}"), .backspaces(2), .text("ê")]))
        core.appActivated(nil, chromiumBrowser: true)
        screen.type("tie", core: &core)
        #expect(core.keyDown(KeyInput(keyCode: 0, modifiers: [], characters: "e"))
                == .swallow([.backspaces(1), .text("ê")]))
    }
    @Test func chromiumVNISequenceLeavesCorrectScreen() {
        var options = Options()
        options.inputMethod = .vni
        var core = TypingCore(enabled: true, options: options, appMemory: [:])
        core.appActivated("com.google.Chrome", chromiumBrowser: true)
        var screen = Screen()
        screen.type("Tie6ng1 ", core: &core)
        expectScalars(screen.text, "Tiếng ")
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
        #expect(screen.key(KeyInput(keyCode: 0, modifiers: [], characters: " "), core: &core)
                == .passAfter([.backspaces(2), .text("ext")]))
        expectScalars(screen.text, "text ")
    }
    @Test func everyResetBoundaryStartsFresh() {
        let resetters: [(inout TypingCore) -> Void] = [
            { $0.mouseDown() }, { $0.inputSourceChanged() }, { $0.reset() },
            { $0.appActivated("app.b", chromiumBrowser: false) }, { $0.appActivated("com.emizuki.daukey", chromiumBrowser: false) },
            { $0.appActivated(nil, chromiumBrowser: false) }, { $0.setEnabled(true) },
            { $0.setOptions(Options()) },
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
        #expect(core.flagsChanged([.control, .shift]) == false)
        #expect(core.flagsChanged([]) == true)
        #expect(!core.snapshot.enabled)
        screen.type("is", core: &core)
        expectScalars(screen.text, "tois")
        _ = core.flagsChanged([.control, .shift])
        #expect(core.flagsChanged([]) == true)
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
        let backspace = KeyInput(keyCode: 0x33, modifiers: [], characters: "")
        #expect(screen.key(backspace, core: &core) == .pass)
        expectScalars(screen.text, "to")
        screen.type("s", core: &core)
        expectScalars(screen.text, "tos")
    }
    @Test func backspaceCanInsertReplacementText() {
        var core = fresh(), screen = Screen()
        screen.type("siste", core: &core)
        expectScalars(screen.text, "sité")
        #expect(screen.key(KeyInput(keyCode: 0x33, modifiers: [], characters: ""), core: &core)
                == .swallow([.backspaces(3), .text("ít")]))
        expectScalars(screen.text, "sít")
    }
    @Test func memoryOwnActivationAndSnapshotChanges() {
        var core = fresh(), screen = Screen()
        let initial = core.snapshot
        screen.type("tieengs", core: &core)
        #expect(core.snapshot == initial)
        core.appActivated("app.a", chromiumBrowser: false)
        core.setEnabled(false)
        let beforeOwn = core.snapshot
        core.appActivated("com.emizuki.daukey", chromiumBrowser: false)
        #expect(core.snapshot == beforeOwn)
        core.setEnabled(true)
        #expect(core.snapshot.appMemory["app.a"] == true)
        core.appActivated("app.b", chromiumBrowser: false)
        core.setEnabled(false)
        core.appActivated("app.a", chromiumBrowser: false)
        #expect(core.snapshot.enabled)
        #expect(core.snapshot.appMemory == ["app.a": true, "app.b": false])
        core.appActivated(nil, chromiumBrowser: false)
        core.setEnabled(false)
        #expect(core.snapshot.appMemory["app.a"] == true)
        let beforeToggle = core.snapshot
        _ = core.flagsChanged([.control, .shift])
        #expect(core.flagsChanged([]) == true)
        #expect(core.snapshot != beforeToggle)
        core.setTap(.unavailable)
        #expect(core.snapshot.tap == .unavailable)
    }
    @Test func eachDisturbanceSpoilsArmedChordEvenWhenDisabled() {
        let disturbances: [(inout TypingCore) -> Void] = [
            { _ = $0.keyDown(KeyInput(keyCode: 0, modifiers: .control, characters: "a")) },
            { $0.mouseDown() }, { $0.reset() }, { $0.appActivated(nil, chromiumBrowser: false) },
            { $0.inputSourceChanged() }, { $0.setEnabled(false) }, { $0.setOptions(Options()) },
        ]
        for disturb in disturbances {
            var core = TypingCore(enabled: false, options: Options(), appMemory: [:])
            _ = core.flagsChanged([.control, .shift])
            disturb(&core)
            #expect(core.flagsChanged([]) == false)
            #expect(!core.snapshot.enabled)
        }
    }
    @Test func emojiAndNonLatinBreaksDoNotCorruptNextWord() {
        var core = fresh(), screen = Screen()
        screen.type("xin👩‍💻дchaof", core: &core)
        expectScalars(screen.text, "xin👩‍💻дchào")
    }
}
