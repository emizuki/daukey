import Testing
import DauKeyEngine
@testable import DauKeyHook

@Suite struct KeyClassifierTests {
    @Test func orderedRules() {
        let rows: [(UInt16, Modifiers, String, Event)] = [
            (0x33, [], "", .backspace), (0x33, .shift, "", .backspace),
            (0x33, .option, "", .reset), (0x33, .command, "", .reset),
            (0x33, .control, "", .reset), (0, .command, "a", .endWord),
            (0, .control, "a", .endWord), (0x7B, .function, "", .endWord),
            (0x24, .shift, "\r\n", .char("\n")), (0x4C, [], "", .char("\n")),
            (0x30, [], "", .char("\t")), (0, .option, "å", .char("å")),
            (0, [.shift, .option], "Å", .char("Å")), (0, .capsLock, "A", .char("A")),
            (0, [], "\u{F700}", .endWord), (0, [], "", .endWord),
            (0, [], "д", .char("д")), (0, [], "ab", .endWord),
            (0, [], "\u{0001}", .endWord), (0, [], "👩‍💻", .char("👩‍💻")),
            (0, [], "a\u{301}", .char("a\u{301}")),
        ]
        for (code, flags, text, expected) in rows {
            #expect(KeyClassifier.classify(KeyInput(keyCode: code, modifiers: flags, characters: text)) == expected)
        }
        for code: UInt16 in [0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79, 0x75, 0x72, 0x35] {
            #expect(KeyClassifier.classify(KeyInput(keyCode: code, modifiers: [], characters: "a")) == .endWord)
        }
    }
}
