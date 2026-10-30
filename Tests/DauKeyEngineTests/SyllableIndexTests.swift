import Testing
@testable import DauKeyEngine

private func completable(_ text: String, _ tone: Tone = .none, _ set: OnsetSet = .native) -> Bool {
    SyllableIndex.`for`(set).contains(Glyph.codes(text), tone: tone)
}

@Suite struct SyllableIndexTests {
    @Test func specExamples() {
        #expect(completable("tien"))       // → tiên
        #expect(completable("tuan"))       // → tuân
        #expect(completable("ươ"))         // → ương
        #expect(completable("bêp"))
        #expect(completable("tiê", .acute))  // → tiến
        #expect(completable(""))
        #expect(!completable("bânn"))
        #expect(!completable("tet", .tilde))
        #expect(!completable("thing"))
        #expect(!completable("ưe"))
        #expect(completable("goong"))
        #expect(!completable("goom"))
        #expect(!completable("abcdefghi"))
    }

    @Test func toneMustMatchUnlessNone() {
        #expect(completable("ta", .grave))   // tàn
        #expect(!completable("tac", .grave))
        #expect(completable("tac"))
        #expect(completable("tac", .acute))
    }

    @Test func everyValidSyllableAndItsPrefixesAreCompletable() {
        for set in OnsetSet.allCases {
            let index = SyllableIndex.`for`(set)
            for onset in Orthography.onsets(set) {
                for nucleus in Orthography.nuclei {
                    for coda in [[]] + Orthography.codas {
                        for tone in Tone.allCases
                        where Orthography.isValid(onset: onset, nucleus: nucleus, coda: coda, tone: tone) {
                            let full = onset + nucleus.codes + coda
                            for length in 0...full.count {
                                #expect(index.contains(Array(full.prefix(length)), tone: tone))
                                #expect(index.contains(Array(full.prefix(length)), tone: .none))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func everyExceptionAndItsPrefixesAreCompletable() {
        for set in OnsetSet.allCases {
            let index = SyllableIndex.`for`(set)
            for exception in Orthography.exceptions {
                if set == .native && exception.needsForeignOnset {
                    #expect(!index.contains(exception.glyphs, tone: exception.tone))
                    continue
                }
                for length in 0...exception.glyphs.count {
                    #expect(index.contains(Array(exception.glyphs.prefix(length)), tone: exception.tone))
                    #expect(index.contains(Array(exception.glyphs.prefix(length)), tone: .none))
                }
            }
        }
    }
}
