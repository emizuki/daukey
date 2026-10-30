import Testing
@testable import DauKeyEngine

@Suite struct SessionCompositionTests {
    @Test(arguments: [
        ("tieengs Vieetj", "tiếng Việt"), ("toi.<s", "tói"), ("toi x< <<s", "tói"),
        ("text ", "text "), ("text\\N", "tẽt\n"),
    ])
    func baselineCompositionAndReopen(_ row: (String, String)) {
        var probe = SessionProbe()
        probe.script(row.0)
        expectSameScalars(probe.text, row.1, row.0)
    }

    @Test func initialTextIsNeverEdited() {
        var probe = SessionProbe(initialText: "xin ")
        probe.script("toi.<s")
        expectSameScalars(probe.text, "xin tói")
        var reopened = SessionProbe(initialText: "a.")
        reopened.script("toi <<s")
        expectSameScalars(reopened.text, "a.tó")
    }

    /// A break that joins the character before it ends the reopen frame, since a Backspace may then delete the whole
    /// character or only the break. Each Unicode scalar of the row is one key; `<` is Backspace.
    @Test(arguments: [("a.\u{301}<", "a."), ("a.\u{301}<s", "a.s"), ("a\u{301}<s", "as")])
    func joiningBreakEndsTheFrame(_ row: (String, String)) {
        var probe = SessionProbe()
        for scalar in row.0.unicodeScalars {
            probe.send(scalar == "<" ? .backspace : .char(Character(scalar)))
        }
        #expect(probe.session.previous == nil, "\(row.0)")
        expectSameScalars(probe.text, row.1, row.0)
    }

    /// 32 keys: the next key is the 33rd.
    static let keys = "tiees" + String(repeating: "b", count: 27)

    @Test(arguments: [
        ("[[", "["), ("[[tieengs ", "[tiếng "), ("[[t<<s", "s"),
        // A bracket break at key 33 is classified before the overflow.
        (keys + "[ ", keys + "[ "),
        // Key 33 starts literal mode, so the later `s` is typed as is instead of undoing the tone.
        (keys + "bs ", "tiế" + String(repeating: "b", count: 28) + "s "),
    ])
    func bracketsAndOverflow(_ row: (String, String)) {
        var probe = SessionProbe()
        probe.script(row.0)
        expectSameScalars(probe.text, row.1, row.0)
    }

    @Test func settingsApplyToNextWord() {
        var frozen = SessionProbe()
        frozen.type("to")
        frozen.session.setOptions(Options(inputMethod: .vni))
        frozen.type("oi to6i")
        #expect(frozen.text == "tôi tôi")

        var reopened = SessionProbe()
        reopened.type("toi ")
        reopened.session.setOptions(Options(inputMethod: .vni))
        reopened.script("<s to6i")
        expectSameScalars(reopened.text, "tói tôi")

        var restoring = SessionProbe()
        restoring.type("tex")
        restoring.session.setOptions(Options(spelling: .off))
        restoring.type("t text ")
        expectSameScalars(restoring.text, "text tẽt ")
    }

    @Test func resetKeepsOptions() {
        var probe = SessionProbe(options: Options(inputMethod: .vni))
        probe.script("to6i |<s to6i")
        expectSameScalars(probe.text, "tôis tôi")
    }
}
