import Testing
import DauKeyEngine
import DauKeyScript

@Suite struct ScriptTests {
    @Test func parsesKeysAndEscapes() {
        #expect(Script.events("a<|") == [.char("a"), .backspace, .reset])
        #expect(Script.events("\\N\\T\\E") == [.char("\n"), .char("\t"), .endWord])
        #expect(Script.events("\\<\\|\\\\") == [.char("<"), .char("|"), .char("\\")])
        #expect(Script.events("x y") == [.char("x"), .char(" "), .char("y")])
    }

    @Test func screenAppliesActions() {
        var screen = Screen()
        screen.apply(.char("t"), .passThrough)
        screen.apply(.char("e"), .passThrough)
        screen.apply(.char("x"), .replace(deleteCount: 1, insert: "ẽ"))
        #expect(Array(screen.string.unicodeScalars) == Array("tẽ".unicodeScalars))
        screen.apply(.char(" "), .replaceThenPass(deleteCount: 1, insert: "ex"))
        #expect(screen.string == "tex ")
        screen.apply(.backspace, .passThrough)
        screen.apply(.endWord, .passThrough)
        screen.apply(.reset, .passThrough)
        #expect(screen.string == "tex")
    }
}
