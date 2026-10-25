import Foundation
import Testing
@testable import DauKeyEngine

@Suite struct RenderTests {
    @Test func everyVowelAndToneIsOnePrecomposedScalar() {
        // Each vowel with the combining mark of its modifier, so expected letters do not come from the table.
        let vowels: [(UInt8, Modifier, String)] = [
            (ASCII.a, .none, ""), (ASCII.a, .breve, "\u{306}"), (ASCII.a, .circumflex, "\u{302}"), (ASCII.e, .none, ""),
            (ASCII.e, .circumflex, "\u{302}"), (ASCII.i, .none, ""), (ASCII.o, .none, ""), (ASCII.o, .circumflex, "\u{302}"),
            (ASCII.o, .horn, "\u{31B}"), (ASCII.u, .none, ""), (ASCII.u, .horn, "\u{31B}"), (ASCII.y, .none, ""),
        ]
        let toneMarks: [Tone: String] = [
            .none: "", .acute: "\u{301}", .grave: "\u{300}", .hook: "\u{309}", .tilde: "\u{303}", .dot: "\u{323}",
        ]
        for (base, modifier, mark) in vowels {
            for uppercase in [false, true] {
                for tone in Tone.allCases {
                    let character = Render.character(Letter(base: base, modifier: modifier, uppercase: uppercase), tone: tone)
                    #expect(character.unicodeScalars.count == 1, "\(base) \(modifier) \(tone) gave \(character)")
                    let plain = String(Character(Unicode.Scalar(uppercase ? base - 32 : base)))
                    let expected = (plain + mark + toneMarks[tone]!).precomposedStringWithCanonicalMapping
                    expectSameScalars(String(character), expected, "\(plain) \(modifier) \(tone)")
                }
            }
        }
    }

    @Test func knownCodePoints() {
        func scalar(_ base: UInt8, _ modifier: Modifier, _ uppercase: Bool, _ tone: Tone) -> UInt32 {
            Render.character(Letter(base: base, modifier: modifier, uppercase: uppercase), tone: tone)
                .unicodeScalars.first!.value
        }
        #expect(scalar(ASCII.e, .circumflex, false, .acute) == 0x1EBF)  // ế
        #expect(scalar(ASCII.u, .horn, false, .dot) == 0x1EF1)          // ự
        #expect(scalar(ASCII.o, .horn, true, .hook) == 0x1EDE)          // Ở
        #expect(scalar(ASCII.a, .breve, false, .tilde) == 0x1EB5)       // ẵ
        #expect(scalar(ASCII.y, .none, true, .dot) == 0x1EF4)           // Ỵ
        #expect(Render.character(Letter(base: ASCII.d, modifier: .stroke, uppercase: true), tone: .none) == "Đ")
        #expect(Render.character(Letter(base: ASCII.q, uppercase: true), tone: .none) == "Q")
    }

    @Test func glyphCodes() {
        #expect(Glyph.codes("ươ") == [Glyph.uHorn, Glyph.oHorn])
        #expect(Glyph.codes("ngh") == [14, 7, 8])
        #expect(Glyph.base(of: Glyph.uHorn) == 21)
        #expect(Glyph.base(of: Glyph.dStroke) == 4)
        #expect(Glyph.isModifiedVowel(Glyph.dStroke) == false)
        #expect(Glyph.isModified(Glyph.dStroke))
        #expect(Letter(key: "Q")?.base == ASCII.q)
        #expect(Letter(key: "Q")?.uppercase == true)
        #expect(Letter(key: "[") == nil)
    }

    @Test func renderPutsToneOnIndex() {
        expectSameScalars(Render.string(elements("toan"), tone: .acute, toneAt: 2), "toán")
        expectSameScalars(Render.string(elements("Đươ"), tone: .grave, toneAt: 2), "Đườ")
        expectSameScalars(Render.string(elements("a1"), tone: .none, toneAt: nil), "a1")
    }
}
