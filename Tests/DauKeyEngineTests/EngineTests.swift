import Testing
@testable import DauKeyEngine
import DauKeyScript

@Suite struct EngineTests {
    // Spec §7.4 table.
    @Test(arguments: [
        ("text ", "text "), ("worry ", "worry "), ("Worry ", "Worry "), ("cheese ", "cheese "), ("things ", "things "),
        ("windows ", "windows "), ("banana ", "banana "), ("Mozilla ", "Mozilla "), ("uow ", "uow "), ("beep ", "bêp "),
        ("tacsz ", "tac "), ("ass ", "as "), ("tests ", "tets "), ("xooong ", "xoong "), ("ddh ", "đh "),
        ("BDDS ", "BĐS "), ("disdain ", "đíain "), ("gieengs ", "giếng "), ("text\\E", "tẽt"), ("text\\N", "tẽt\n"),
        ("text.", "text."), ("tieengs ", "tiếng "), ("text\\T", "tẽt\t"), ("ddanhw ", "ddanhw "), ("ddyeu ", "ddyeu "),
        ("ddangg ", "đangg "), ("ddxas ", "đxá "), ("ddqu ", "đqu "),
    ])
    func restoreAtWordEnd(_ row: (String, String)) {
        expectSameScalars(typed(row.0), row.1, row.0)
    }

    @Test func checkModeNeverRestores() {
        expectSameScalars(typed("text ", .check), "tẽt ")
        expectSameScalars(typed("text ", .off), "tẽt ")
    }

    @Test func restoreActionIsADiffThenPass() {
        var engine = Engine()
        for character in "text" { _ = engine.handle(.char(character)) }
        #expect(engine.handle(.char(" ")) == .replaceThenPass(deleteCount: 2, insert: "ext"))
        var shortcut = Engine()
        for character in "text" { _ = shortcut.handle(.char(character)) }
        #expect(shortcut.handle(.endWord) == .passThrough)
    }

    @Test func passThroughWhenTheKeyJustAppears() {
        var engine = Engine()
        #expect(engine.handle(.char("t")) == .passThrough)
        #expect(engine.handle(.char("i")) == .passThrough)
        #expect(engine.handle(.char("e")) == .passThrough)
        #expect(engine.handle(.char("e")) == .replace(deleteCount: 1, insert: "ê"))
        #expect(engine.handle(.char("n")) == .passThrough)
        #expect(engine.handle(.char("s")) == .replace(deleteCount: 2, insert: "ến"))
        #expect(engine.handle(.backspace) == .passThrough)
        expectSameScalars(engine.display, "tiế")
    }

    // Spec §4.3 examples.
    @Test(arguments: [
        ("toi.<s", "tói"), ("toi x<<s", "tói"), ("toi\\N<s", "tois"), ("toi x< <<s", "tói"), ("toi|<s", "tos"),
        ("toi |<s", "tois"), ("lwo.<uwn<<", "lwou"), ("lwo.<nwn<<", "lwon"),
        ("lwo.<uwdd<d", "lwouwdd"),
        ("text <<<s", "té"), ("beep <s", "bếp"), ("x[0]", "xơ0ư"), ("a[", "a["), ("[]", "ơ]"), ("[o[", "ô["),
    ])
    func eventHandling(_ row: (String, String)) {
        expectSameScalars(typed(row.0), row.1, row.0)
    }

    @Test func reopenStateAndCounters() {
        var engine = Engine()
        for event in Script.events("toi x< ") { _ = engine.handle(event) }
        #expect(engine.previous?.keys == Array("toi"))
        #expect(engine.breaksAfterPrevious == 2)
        _ = engine.handle(.backspace)
        _ = engine.handle(.backspace)
        #expect(engine.keys == Array("toi"))
        #expect(engine.previous == nil)
    }

    @Test func overflowStaysLiteral() {
        let long = String(repeating: "b", count: 32)
        expectSameScalars(typed(long + "bas", .off), long + "bas")
        var engine = Engine()
        for character in "tiees" + String(repeating: "b", count: 28) { _ = engine.handle(.char(character)) }
        #expect(engine.mode == .literal)
        _ = engine.handle(.backspace)
        #expect(engine.mode == .literal)
    }

    @Test func keyThirtyTwoStillComposes() {
        let prefix = String(repeating: "b", count: 30)
        expectSameScalars(typed(prefix + "as", .off), prefix + "á")
    }

    @Test func bracketThatBreaksAtTheLimitFinishesTheWord() {
        // Spec §4.1 classifies the key before §4.2 counts it: a bracket that does not resolve is a break, even as key 33.
        let keys = "tiees" + String(repeating: "b", count: 27)
        expectSameScalars(typed(keys + "[ "), keys + "[ ")
    }

    @Test(arguments: [
        ("[[tieengs ", "[tiếng "), ("{{Vieetj ", "{Việt "), ("[[[", "[ơ"), ("[[w", "[ư"), ("[[dd", "[đ"),
        ("[[tests ", "[tets "), ("[[t<<s", "s"),
    ])
    func escapedBracketWordEndsBeforeTheNextKey(_ row: (String, String)) {
        // Spec §4.3: a word holding only an escaped bracket ends before the next word character, with no reopen.
        expectSameScalars(typed(row.0), row.1, row.0)
    }

    @Test func bracketsInLiteralWordsAreAppended() {
        let long = String(repeating: "b", count: 33)
        var engine = Engine()
        for character in long + "[" { _ = engine.handle(.char(character)) }
        #expect(engine.mode == .literal)
        #expect(engine.display == long + "[")
        expectSameScalars(typed("text <["), "text[")
    }

    @Test func tabIsAHardBreak() {
        var engine = Engine()
        for character in "text" { _ = engine.handle(.char(character)) }
        #expect(engine.handle(.char("\t")) == .passThrough)
        expectSameScalars(typed("toi\\T<s"), "tois")
    }

    @Test func vniDigitsAtWordStartAreBreaks() {
        expectSameScalars(typed("1a6", .vni), "1â")
        expectSameScalars(typed("2024 la8m", .vni), "2024 lăm")
        expectSameScalars(typed("tie6ng1 ", .vni), "tiếng ")
    }

    @Test func optionsChangeIsAReset() {
        var engine = Engine()
        for character in "tieeng" { _ = engine.handle(.char(character)) }
        engine.options = Options(inputMethod: .vni)
        #expect(engine.keys.isEmpty)
        #expect(engine.previous == nil)
        #expect(engine.handle(.char("a")) == .passThrough)
        #expect(engine.handle(.char("1")) == .replace(deleteCount: 1, insert: "á"))
    }

    @Test func diffKeepsTheCommonPrefix() {
        let restore = Engine.diff("tẽt", "text")
        #expect(restore.deleteCount == 2 && restore.insert == "ext")
        let same = Engine.diff("abc", "abc")
        #expect(same.deleteCount == 0 && same.insert.isEmpty)
        let grow = Engine.diff("", "a")
        #expect(grow.deleteCount == 0 && grow.insert == "a")
    }
}
