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

    /// The restore edit keeps the common prefix: it deletes only what differs and passes the break after it.
    @Test func restoreActionIsADiffThenPass() {
        var session = TypingSession()
        for character in "text" { _ = session.handle(.char(character)) }
        #expect(session.handle(.char(" ")) == .replaceThenPass(deleteCount: 2, insert: "ext"))
        var shortcut = TypingSession()
        for character in "text" { _ = shortcut.handle(.char(character)) }
        #expect(shortcut.handle(.endWord) == .passThrough)
    }

    @Test func passThroughWhenTheKeyJustAppears() {
        var session = TypingSession()
        #expect(session.handle(.char("t")) == .passThrough)
        #expect(session.handle(.char("i")) == .passThrough)
        #expect(session.handle(.char("e")) == .passThrough)
        #expect(session.handle(.char("e")) == .replace(deleteCount: 1, insert: "ê"))
        #expect(session.handle(.char("n")) == .passThrough)
        #expect(session.handle(.char("s")) == .replace(deleteCount: 2, insert: "ến"))
        #expect(session.handle(.backspace) == .passThrough)
        expectSameScalars(session.display, "tiế")
    }

    /// An edit from nothing deletes nothing, and a boundary that leaves the text as it is sends no edit.
    @Test func editsDeleteOnlyWhatDiffers() {
        var grow = TypingSession()
        #expect(grow.handle(.char("w")) == .replace(deleteCount: 0, insert: "ư"))
        var same = TypingSession(rules: RuleTables(exclusions: ["toi"]))
        for character in "toi" { _ = same.handle(.char(character)) }
        #expect(same.handle(.char(" ")) == .passThrough)
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

    /// Deleting every break after a word reopens that word, not the one typed and deleted after it.
    @Test func reopenAfterDeletingBreaksEditsTheWord() {
        expectSameScalars(typed("toi x< "), "toi  ")
        expectSameScalars(typed("toi x< <<"), "toi")
        expectSameScalars(typed("toi x< <<s"), "tói")
        expectSameScalars(typed("toi x< <<<s"), "tó")
    }

    @Test func overflowStaysLiteral() {
        let long = String(repeating: "b", count: 32)
        expectSameScalars(typed(long + "bas", .off), long + "bas")
        var session = TypingSession()
        for character in "tiees" + String(repeating: "b", count: 28) { _ = session.handle(.char(character)) }
        #expect(session.mode == .literal)
        _ = session.handle(.backspace)
        #expect(session.mode == .literal)
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
        var session = TypingSession()
        for character in long + "[" { _ = session.handle(.char(character)) }
        #expect(session.mode == .literal)
        #expect(session.display == long + "[")
        expectSameScalars(typed("text <["), "text[")
    }

    @Test func tabIsAHardBreak() {
        var session = TypingSession()
        for character in "text" { _ = session.handle(.char(character)) }
        #expect(session.handle(.char("\t")) == .passThrough)
        expectSameScalars(typed("toi\\T<s"), "tois")
    }

    @Test func vniDigitsAtWordStartAreBreaks() {
        expectSameScalars(typed("1a6", .vni), "1â")
        expectSameScalars(typed("2024 la8m", .vni), "2024 lăm")
        expectSameScalars(typed("tie6ng1 ", .vni), "tiếng ")
    }

    /// New options apply from the next word; the word being typed keeps its own and is not rendered again.
    @Test func optionsApplyToTheNextWord() {
        var probe = SessionProbe()
        probe.type("tieeng")
        probe.session.setOptions(Options(inputMethod: .vni))
        probe.type("s a1")
        expectSameScalars(probe.text, "tiếng á")
    }

    /// Typed case is kept with auto-capitalize off; at a known document start the first cased letter of a sentence is
    /// capitalized after composition, and Backspace keeps the decision only where the sentence start is known.
    @Test(arguments: [
        ("Tooi", false, "Tôi"), ("tooi", false, "tôi"), ("Ddieeu", false, "Điêu"), ("Thaamj", false, "Thậm"),
        ("Giowf", false, "Giờ"), ("chao ban. toi", false, "chao ban. toi"),
        ("ee", true, "Ê"), ("ees", true, "Ế"), ("chao", true, "Chao"), ("tooi", true, "Tôi"), ("ddieeu", true, "Điêu"),
        ("thaamj", true, "Thậm"), ("giowf", true, "Giờ"), ("dd", true, "Đ"), ("ddi", true, "Đi"),
        ("dduowjc", true, "Được"), ("aw", true, "Ă"), ("awn", true, "Ăn"), ("aa", true, "Â"), ("aans", true, "Ấn"),
        ("eems", true, "Ếm"), ("oo", true, "Ô"), ("oong", true, "Ông"), ("ow", true, "Ơ"), ("owi", true, "Ơi"),
        ("owr", true, "Ở"), ("uw", true, "Ư"), ("uowsc", true, "Ước"), ("w", true, "Ư"), ("[", true, "Ơ"),
        ("[i", true, "Ơi"), ("]", true, "Ư"), ("as", true, "Á"), ("af", true, "À"), ("ar", true, "Ả"),
        ("ax", true, "Ã"), ("aj", true, "Ạ"), ("asnh", true, "Ánh"),
        ("chao ban. toi", true, "Chao ban. Toi"), ("chao ban! toi", true, "Chao ban! Toi"),
        ("chao ban? toi", true, "Chao ban? Toi"), ("chao ban\\Ntoi", true, "Chao ban\nToi"), ("3.14", true, "3.14"),
        ("chao\\N< ban", true, "Chao ban"), ("chao\\N\\N<ban", true, "Chao\nBan"),
        ("chao\\N\\N<< ban", true, "Chao ban"), ("c<d", true, "D"), ("C<d", true, "D"), ("Chao<<<<c", true, "C"),
        ("Chao <<<<<c", true, "C"), ("Chao ban<<<<<<<<c", true, "C"), ("C<<c", true, "C"),
        ("Chao<<<<<<<<c", true, "C"),
    ])
    func sentenceCasingAtAKnownDocumentStart(_ row: (String, Bool, String)) {
        var probe = SessionProbe(
            settings: SessionSettings(autoCapitalize: row.1),
            context: TextContext(prefix: "", startsAtDocumentStart: true)
        )
        probe.script(row.0)
        expectSameScalars(probe.text, row.2, row.0)
    }

    @Test func exclusionsBypassVietnameseComposition() {
        let rules = RuleTables(exclusions: ["code", "admin", "docker"])
        for (keys, expected) in [("code ", "code "), ("admin ", "admin "), ("docker ", "docker "), ("tooi ", "tôi ")] {
            var probe = SessionProbe(rules: rules)
            probe.script(keys)
            expectSameScalars(probe.text, expected, keys)
        }
    }

    @Test func macrosExpandSingleWordTriggers() {
        let rules = RuleTables(macros: [
            MacroRule(trigger: "vn", replacement: "Việt Nam"), MacroRule(trigger: "hn", replacement: "Hà Nội"),
        ])
        for (keys, expected) in [("vn ", "Việt Nam "), ("hn ", "Hà Nội "), ("chao ", "chao ")] {
            var probe = SessionProbe(rules: rules)
            probe.script(keys)
            expectSameScalars(probe.text, expected, keys)
        }
    }
}
