import Testing
@testable import DauKeyEngine

private func isValid(_ text: String, _ tone: Tone = .none, _ set: OnsetSet = .native) -> Bool {
    Orthography.split(Glyph.codes(text), tone: tone, onsets: set) != nil
}

@Suite struct OrthographyTests {
    @Test func tableSizes() {
        #expect(Orthography.nuclei.count == 56)
        #expect(Orthography.onsets(.native).count == 28)  // includes the empty onset
        #expect(Orthography.onsets(.foreignTelex).count == 31)
        #expect(Orthography.onsets(.foreignVNI).count == 32)
    }

    @Test(arguments: [
        "tiêng", "viêc", "huynh", "quynh", "thich", "xoeng", "tuyp", "khuâng", "bêp",
        "giêng", "giêc", "gia", "gi", "gin", "gim", "quy", "quyt", "quơn", "ngoao", "nguêu", "goong", "sooc", "khuyu", "uơ", "thuơ",
        "ương", "ngươi", "tuân", "hoăc", "khuya", "ngoeo", "a", "ơi", "nghiêng", "đươc",
    ])
    func validSyllables(_ text: String) {
        #expect(isValid(text), "\(text)")
    }

    @Test(arguments: [
        "thing", "onh", "gym", "bưp", "quych", "tuyêc", "qa", "quu", "quư", "gii", "ươ", "goo", "ă", "tiê",
        "uâ", "ech", "tic", "buan", "dza", "za", "fa", "kafka", "yn", "oep", "huêt", "uyêng", "ưp",
        "ka", "kan", "ci", "cy", "ge", "gê", "gha", "nge", "ngi", "ngha", "byên", "thyêu", "yt", "byt", "boa", "phuy",
        "muyên", "voăn",
    ])
    func invalidSyllables(_ text: String) {
        #expect(!isValid(text), "\(text)")
    }

    @Test func stopCodaToneRule() {
        #expect(isValid("tac", .none))
        #expect(isValid("tac", .acute))
        #expect(isValid("tac", .dot))
        #expect(!isValid("tac", .grave))
        #expect(!isValid("tac", .hook))
        #expect(!isValid("tet", .tilde))
        #expect(isValid("tan", .tilde))
    }

    @Test func foreignOnsets() {
        #expect(isValid("za", .none, .foreignTelex))
        #expect(isValid("fan", .none, .foreignTelex))
        #expect(!isValid("wa", .none, .foreignTelex))
        #expect(isValid("wa", .none, .foreignVNI))
    }

    @Test func splitsPreferTheLongestValidOnset() {
        #expect(Orthography.split(Glyph.codes("gia"), tone: .grave, onsets: .native) == Split(onset: 2, nucleus: 1, coda: 0))
        #expect(Orthography.split(Glyph.codes("gi"), tone: .grave, onsets: .native) == Split(onset: 1, nucleus: 1, coda: 0))
        #expect(Orthography.split(Glyph.codes("giêng"), tone: .acute, onsets: .native) == Split(onset: 1, nucleus: 2, coda: 2))
        #expect(Orthography.split(Glyph.codes("quy"), tone: .acute, onsets: .native) == Split(onset: 2, nucleus: 1, coda: 0))
        #expect(Orthography.split(Glyph.codes("ngươi"), tone: .grave, onsets: .native) == Split(onset: 2, nucleus: 3, coda: 0))
    }

    @Test func exceptionsInEveryOnsetSet() {
        for set in OnsetSet.allCases {
            #expect(Orthography.split(Glyph.codes("krông"), tone: .none, onsets: set) == Split(onset: 2, nucleus: 1, coda: 2))
            #expect(Orthography.split(Glyph.codes("eacha"), tone: .grave, onsets: set) == Split(onset: 4, nucleus: 1, coda: 0))
            #expect(Orthography.split(Glyph.codes("lăk"), tone: .acute, onsets: set) == Split(onset: 1, nucleus: 1, coda: 1))
            #expect(Orthography.split(Glyph.codes("lăk"), tone: .dot, onsets: set) == nil)
        }
        #expect(Orthography.exceptions.count == 111)
    }

    @Test func regionSkipsOnsetLetters() {
        #expect(Region.of(elements("qua")) == 2...2)
        #expect(Region.of(elements("qu")) == nil)
        #expect(Region.of(elements("gia")) == 2...2)
        #expect(Region.of(elements("gin")) == 1...1)
        #expect(Region.of(elements("bxa")) == 2...2)
        #expect(Region.of(elements("ưindo")) == 0...4)
        #expect(Region.of(elements("th")) == nil)
        #expect(Region.of(elements("Qua")) == 2...2)
    }
}
