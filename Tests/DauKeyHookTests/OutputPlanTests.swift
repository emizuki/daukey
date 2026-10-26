import Testing
import DauKeyEngine
@testable import DauKeyHook

@Suite struct OutputPlanTests {
    @Test func chromiumPlaceholderOnlyForDeletions() {
        #expect(OutputPlan.decision(for: .replace(deleteCount: 2, insert: "ê"), chromiumBrowser: true)
                == .swallow([.text("\u{202F}"), .backspaces(3), .text("ê")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 1, insert: "ext"), chromiumBrowser: true)
                == .passAfter([.text("\u{202F}"), .backspaces(2), .text("ext")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: "x"), chromiumBrowser: true)
                == .swallow([.text("x")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 0, insert: ""), chromiumBrowser: true)
                == .passAfter([]))
        #expect(OutputPlan.decision(for: .passThrough, chromiumBrowser: true) == .pass)
    }
    @Test func actionsAndEmptySteps() {
        #expect(OutputPlan.decision(for: .passThrough, chromiumBrowser: false) == .pass)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 2, insert: "á"), chromiumBrowser: false) == .swallow([.backspaces(2), .text("á")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 1, insert: "ext"), chromiumBrowser: false) == .passAfter([.backspaces(1), .text("ext")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: ""), chromiumBrowser: false) == .swallow([]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 0, insert: "x"), chromiumBrowser: false) == .passAfter([.text("x")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 1, insert: ""), chromiumBrowser: false) == .swallow([.backspaces(1)]))
    }
    @Test func chunksRespectUTF16BoundaryAndWholeCharacters() {
        let twenty = String(repeating: "á", count: 20)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: twenty), chromiumBrowser: false) == .swallow([.text(twenty)]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: twenty + "b"), chromiumBrowser: false) == .swallow([.text(twenty), .text("b")]))
        let nineteen = String(repeating: "a", count: 19)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: nineteen + "😀b"), chromiumBrowser: false) == .swallow([.text(nineteen), .text("😀b")]))
    }
}
