import Testing
@testable import DauKeyEngine

@Suite struct ToneKeyTests {
    @Test(arguments: [
        ("as", "á"), ("af", "à"), ("ar", "ả"), ("ax", "ã"), ("aj", "ạ"), ("asf", "à"), ("ass", "as"),
        ("asss", "ass"), ("asz", "a"), ("az", "az"), ("qus", "qus"), ("gif", "gì"), ("bafcs", "bác"),
        ("baxtj", "bạt"), ("taxxi", "taxi"), ("AS", "Á"), ("aS", "á"), ("bxas", "bxas"), ("toans", "toán"),
        ("tosan", "toán"), ("tacsz", "tac"), ("texts", "tét"), ("bafcz", "bac"), ("asqz", "áqz"),
    ])
    func telexTones(_ row: (String, String)) {
        expectSameScalars(composed(row.0), row.1, row.0)
    }

    @Test(arguments: [
        ("a1", "á"), ("a11", "a1"), ("a10", "a"), ("a2", "à"), ("a5", "ạ"), ("ba2c1", "bác"), ("a1q0", "áq0"),
    ])
    func vniTones(_ row: (String, String)) {
        expectSameScalars(composed(row.0, .vni), row.1, row.0)
    }

    @Test func offModeStartsASegmentAtALetterThatCannotBeVietnamese() {
        // Spec §5.9: with spelling off, `x` starts a segment, so `s` tones the `a` after it.
        expectSameScalars(composed("bxas", .off), "bxá")
        expectSameScalars(composed("bxas", .check), "bxas")
    }

    @Test func toneKeysTrackProvenance() {
        let composer = Composer(options: Options())
        let w = composer.compose(Array("asz"))
        #expect(w.tone == .none)
        #expect(w.toneKeys == [1, 2])
        #expect(w.toneAnchor == 0)
        let undone = composer.compose(Array("ass"))
        #expect(undone.slots.map(\.own) == [[0], [2, 1]])
        #expect(undone.escaped == ["s"])
    }

    @Test func otherElementsAreNeverCompletable() {
        let composer = Composer(options: Options())
        #expect(!composer.isCompletable(composer.compose(Array("[[a"))))
        #expect(!composer.isCompletable(composer.compose(Array("a6"))))
        #expect(composer.isCompletable(composer.compose(Array("a"))))
    }
}
