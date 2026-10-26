import Testing
@testable import DauKeyEngine

@Suite struct SimpleTelexTests {
    @Test func standaloneWStaysLiteralInsteadOfInsertingHornU() {
        for (keys, expected) in [("w", "w"), ("W", "W"), ("ww", "ww"), ("thw", "thw")] {
            expectSameScalars(composed(keys, Options(inputMethod: .simpleTelex)), expected, keys)
        }
        expectSameScalars(composed("w"), "ư")
        expectSameScalars(composed("W"), "Ư")
    }
    @Test func existingVowelsStillReceiveTelexTransforms() {
        for options in Options.all where options.inputMethod == .simpleTelex {
            for (keys, expected) in [
                ("aw", "ă"), ("ow", "ơ"), ("uw", "ư"), ("uow", "ươ"),
                ("aa", "â"), ("ee", "ê"), ("oo", "ô"), ("dd", "đ"), ("aws", "ắ"),
                ("[", "ơ"), ("]", "ư"), ("{", "Ơ"), ("}", "Ư"),
                ("thuowr", "thuở"), ("dduwowcj", "được"),
            ] {
                expectSameScalars(composed(keys, options), expected, "\(keys), \(options)")
            }
        }
    }

    @Test func modifierUndoAndReapplicationKeepTheOriginalVowel() {
        let options = Options(inputMethod: .simpleTelex)
        expectSameScalars(composed("aww", options), "aw")
        expectSameScalars(composed("uoww", options), "uow")
        expectSameScalars(typed("aww<w", options), "ă")
    }

    @Test func backspaceReopensWordsAndEscapedBracketsKeepTheirBoundary() {
        let options = Options(inputMethod: .simpleTelex)
        for (keys, expected) in [
            ("toi.<s", "tói"), ("beep <s", "bếp"), ("tieengs<", "tiến"),
            ("[[tieengs ", "[tiếng "), ("[[w", "[w"), ("sdd[d<", "sd"),
        ] {
            expectSameScalars(typed(keys, options), expected, keys)
        }
    }

    @Test func restoreDependsOnSpellingModeNotTheTelexVariant() {
        for spelling in Spelling.allCases {
            let options = Options(inputMethod: .simpleTelex, spelling: spelling)
            expectSameScalars(typed("text ", options), spelling == .checkAndRestore ? "text " : "tẽt ")
            expectSameScalars(typed("tooi yeeu tieengs vieetj ", options), "tôi yêu tiếng việt ")
        }
    }

    @Test func foreignOnsetsUseTheTelexPolicyWithoutAddingW() {
        let options = Options(inputMethod: .simpleTelex, allowForeignConsonants: true)
        expectSameScalars(typed("fas ", options), "fá ")
        expectSameScalars(typed("was ", options), "was ")
        expectSameScalars(typed("fas ", Options(inputMethod: .simpleTelex)), "fas ")
    }

    @Test func changingMethodsClearsCompositionAndChangesStandaloneWBehavior() {
        for first in InputMethod.allCases {
            for second in InputMethod.allCases where first != second {
                var engine = Engine(options: Options(inputMethod: first))
                for key in "toi " { _ = engine.handle(.char(key)) }
                for key in "tiee" { _ = engine.handle(.char(key)) }
                engine.options = Options(inputMethod: second)
                _ = engine.handle(.char("w"))
                expectSameScalars(engine.display, second == .telex ? "ư" : "w")
                #expect(engine.previous == nil)
            }
        }
    }
}
