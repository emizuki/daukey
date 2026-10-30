import Testing
@testable import DauKeyEngine
import DauKeyScript

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

    /// Changing the method mid-word keeps the word in the method it started with; the next word uses the new one.
    @Test func changingMethodsAppliesToTheNextWordAndChangesStandaloneWBehavior() {
        for first in InputMethod.allCases {
            for second in InputMethod.allCases where first != second {
                var session = TypingSession(options: Options(inputMethod: first))
                var screen = Screen()
                for event in Script.events("toi tiee") { screen.apply(event, session.handle(event)) }
                session.setOptions(Options(inputMethod: second))
                // The word being typed keeps the first method; the next word uses the second.
                for event in Script.events("n w") { screen.apply(event, session.handle(event)) }
                expectSameScalars(session.display, second == .telex ? "ư" : "w")
                expectSameScalars(screen.string, (first == .vni ? "toi tieen " : "toi tiên ") + session.display)
            }
        }
    }
}
