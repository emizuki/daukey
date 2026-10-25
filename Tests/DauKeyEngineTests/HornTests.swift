import Testing
@testable import DauKeyEngine

@Suite struct HornTests {
    // Spec §5.5 example table.
    @Test(arguments: [
        ("uaw", "ưa"), ("quaw", "quă"), ("quonwr", "quởn"), ("oaw", "oă"), ("uiw", "ưi"), ("uuw", "ưu"),
        ("uow", "ươ"), ("huow", "hươ"), ("nguow", "ngươ"), ("u[w", "ươ"), ("nguoiwf", "người"),
        ("uongw", "ương"), ("uoww", "uow"), ("thuow", "thuơ"), ("thuowr", "thuở"), ("thuoww", "thươ"),
        ("thuowww", "thuow"), ("uuww", "uuw"), ("w", "ư"), ("W", "Ư"), ("nhw", "như"), ("ww", "w"), ("nhww", "nhw"),
        ("wsw", "w"), ("woww", "wow"), ("[w", "[w"), ("aww", "aw"), ("ew", "ew"), ("hu[", "huơ"), ("WW", "W"),
        ("WoWw", "Wow"), ("ddiw", "điw"), ("awua", "ăua"),
    ])
    func telexHorn(_ row: (String, String)) {
        expectSameScalars(composed(row.0), row.1, row.0)
    }

    // Spec §5.1 step 3 horn normalisation.
    @Test(arguments: [
        ("thuown", "thươn"), ("tuwoi", "tươi"), ("hu[n", "hươn"), ("thuowss", "thuơs"), ("ruowuj", "rượu"),
        ("tuwoc", "tươc"), ("tuwom", "tươm"), ("tuwop", "tươp"), ("tuwot", "tươt"), ("hu[u", "hươu"),
        ("dduwowcj", "được"), ("DDUWOWNGF", "ĐƯỜNG"), ("awa", "â"), ("owo", "ô"), ("aaw", "ă"),
    ])
    func normalisationAndSwitching(_ row: (String, String)) {
        expectSameScalars(composed(row.0), row.1, row.0)
    }

    @Test(arguments: [
        ("u7", "ư"), ("o7", "ơ"), ("a8", "ă"), ("uo7", "ươ"), ("thuo7", "thuơ"), ("thuo73", "thuở"),
        ("uo7n", "ươn"), ("uon7", "ươn"), ("a7", "a7"), ("u8", "u8"), ("a88", "a8"), ("mu7a8", "mưa8"), ("a87", "ă7"),
        ("nguo7i2", "người"), ("d9uo7c5", "được"), ("a8u6", "ău6"),
    ])
    func vniHornAndBreve(_ row: (String, String)) {
        expectSameScalars(composed(row.0, .vni), row.1, row.0)
    }

    // Spec §5.8.
    @Test(arguments: [
        ("[", "ơ"), ("th[", "thơ"), ("t]", "tư"), ("T}", "TƯ"), ("{", "Ơ"), ("{s", "Ớ"), ("nh]f", "nhừ"), ("u[", "uơ"), ("[s", "ớ"),
        ("][", "ươ"), ("w[", "ươ"), ("ng]owif", "người"), ("[[", "["), ("th[[", "th["), ("th[[[", "th[["),
    ])
    func brackets(_ row: (String, String)) {
        expectSameScalars(composed(row.0), row.1, row.0)
    }

    @Test func bracketThatCannotComposeBreaks() {
        let composer = Composer(options: Options())
        #expect(composer.compose(Array("a[")).lastKeyBroke)
        #expect(composer.compose(Array("[]")).lastKeyBroke)
        #expect(composer.compose(Array("[o[")).lastKeyBroke)
        #expect(!composer.compose(Array("[[")).lastKeyBroke)
        expectSameScalars(composer.display(Array("[o")), "ô")
    }

    @Test func offModeStillGates() {
        // Spec §5.1: gating applies in `.off` too; only the segments of §5.9 differ.
        expectSameScalars(composed("muaw", .off), "mưa")
        expectSameScalars(composed("luu7", .vniOff), "lưu")
        expectSameScalars(composed("uouo7", .vniOff), "uouơ")
        expectSameScalars(composed("thuoa7", .vniOff), "thuoa7")
    }

    @Test func strokeAfterAnEscapedBracket() {
        // Composer level only: the engine itself starts a new word after `[[` (spec §4.3). Lives here because it
        // needs real brackets. With spelling on, a segment holding `other` is not completable, so the stroke is refused.
        expectSameScalars(composed("[[dd"), "[dd")
        // With spelling off, `d` starts a segment after the bracket, and the stroke applies there (spec §5.9).
        expectSameScalars(composed("[[dd", .off), "[đ")
    }

    @Test func sourceIsClearedWhenAnotherKeyChangesTheModifier() {
        let w = Composer(options: Options()).compose(Array("[o"))
        #expect(w.letter(0)?.source == nil)
        #expect(w.letter(0)?.modifier == .circumflex)
    }
}
