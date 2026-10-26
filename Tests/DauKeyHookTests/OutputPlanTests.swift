import Testing
import DauKeyEngine
@testable import DauKeyHook

@Suite struct OutputPlanTests {
    @Test func actionsAndEmptySteps() {
        #expect(OutputPlan.decision(for: .passThrough) == .pass)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 2, insert: "á")) == .swallow([.backspaces(2), .text("á")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 1, insert: "ext")) == .passAfter([.backspaces(1), .text("ext")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: "")) == .swallow([]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 0, insert: "x")) == .passAfter([.text("x")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 1, insert: "")) == .swallow([.backspaces(1)]))
    }
    @Test func chunksRespectUTF16BoundaryAndWholeCharacters() {
        let twenty = String(repeating: "á", count: 20)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: twenty)) == .swallow([.text(twenty)]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: twenty + "b")) == .swallow([.text(twenty), .text("b")]))
        let nineteen = String(repeating: "a", count: 19)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: nineteen + "😀b")) == .swallow([.text(nineteen), .text("😀b")]))
    }
}
