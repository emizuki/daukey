import Testing
@testable import DauKeyEngine
import DauKeyScript

/// Inputs from the plan's Review Focus list.
@Suite struct ReviewFocusTests {
    @Test func capsLockWords() {
        expectSameScalars(typed("VIEETJ NAM"), "VIỆT NAM")
        expectSameScalars(typed("DDUWOWNGF "), "ĐƯỜNG ")
    }

    @Test func nonASCIIBetweenWords() {
        expectSameScalars(typed("xin😀chaof"), "xin😀chào")
        expectSameScalars(typed("tieengs€tee "), "tiếng€tê ")
        expectSameScalars(typed("xin👍🏽chaof"), "xin👍🏽chào")  // a multi-scalar character is one break
    }

    @Test func optionChangeMidWordStartsClean() {
        var engine = Engine()
        var screen = Screen()
        for event in Script.events("tieeng") { screen.apply(event, engine.handle(event)) }
        engine.options = Options(inputMethod: .vni)
        for event in Script.events("a1") { screen.apply(event, engine.handle(event)) }
        expectSameScalars(screen.string, "tiêngá")
    }

    @Test func longBackspaceRunsReopenOnlyTheLastWord() {
        expectSameScalars(typed("toi nay vui<<<<<<<<s"), "tois")
        expectSameScalars(typed("ab<<<<<<"), "")
        var engine = Engine()
        var screen = Screen()
        for event in Script.events("viet nam" + String(repeating: "<", count: 20)) {
            let action = engine.handle(event)
            if case .replace(let count, _) = action { #expect(count <= screen.text.count) }
            screen.apply(event, action)
        }
        #expect(screen.string.isEmpty)
    }

    @Test func closingBracketAfterAWordWithStroke() {
        expectSameScalars(typed("[[Caif ddawtj] "), "[Cài đặt] ")
        expectSameScalars(typed("[[ddi] "), "[đi] ")
        expectSameScalars(typed("[[Caif ddawtj] ", .off), "[Cài đặt] ")
    }

    @Test func vniNumbers() {
        expectSameScalars(typed("2024 la8m", .vni), "2024 lăm")
        expectSameScalars(typed("1a6", .vni), "1â")
    }
}
