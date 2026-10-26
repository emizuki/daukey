import Testing
import DauKeyEngine
@testable import DauKeyHook

@Suite struct OutputPlanTests {
    @Test func spotlightBundleIDsMatchExactly() {
        #expect(SpotlightTarget.matches(bundleID: "com.apple.Spotlight"))
        #expect(SpotlightTarget.matches(bundleID: "com.apple.campo"))
        #expect(!SpotlightTarget.matches(bundleID: nil))
        #expect(!SpotlightTarget.matches(bundleID: "com.apple.spotlight"))
        #expect(!SpotlightTarget.matches(bundleID: "com.google.Chrome"))
    }
    @Test func spotlightSelectionTakesPrecedenceOverInlineCompletionWorkaround() {
        for inlineCompletionApp in [false, true] {
            #expect(OutputPlan.decision(for: .replace(deleteCount: 2, insert: "ê"),
                    inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: true)
                    == .swallow([.selectBackward(2), .text("ê")]))
            #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 1, insert: "ext"),
                    inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: true)
                    == .passAfter([.selectBackward(1), .text("ext")]))
            #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: "x"),
                    inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: true) == .swallow([.text("x")]))
            #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 0, insert: ""),
                    inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: true) == .passAfter([]))
            #expect(OutputPlan.decision(for: .passThrough,
                    inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: true) == .pass)
        }
    }
    @Test func inlineCompletionPlaceholderOnlyForDeletions() {
        #expect(OutputPlan.decision(for: .replace(deleteCount: 2, insert: "ê"), inlineCompletionApp: true, targetIsSpotlight: false)
                == .swallow([.text("\u{202F}"), .backspaces(3), .text("ê")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 1, insert: "ext"), inlineCompletionApp: true, targetIsSpotlight: false)
                == .passAfter([.text("\u{202F}"), .backspaces(2), .text("ext")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: "x"), inlineCompletionApp: true, targetIsSpotlight: false)
                == .swallow([.text("x")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 0, insert: ""), inlineCompletionApp: true, targetIsSpotlight: false)
                == .passAfter([]))
        #expect(OutputPlan.decision(for: .passThrough, inlineCompletionApp: true, targetIsSpotlight: false) == .pass)
    }
    @Test func actionsAndEmptySteps() {
        #expect(OutputPlan.decision(for: .passThrough, inlineCompletionApp: false, targetIsSpotlight: false) == .pass)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 2, insert: "á"), inlineCompletionApp: false, targetIsSpotlight: false) == .swallow([.backspaces(2), .text("á")]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 1, insert: "ext"), inlineCompletionApp: false, targetIsSpotlight: false) == .passAfter([.backspaces(1), .text("ext")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: ""), inlineCompletionApp: false, targetIsSpotlight: false) == .swallow([]))
        #expect(OutputPlan.decision(for: .replaceThenPass(deleteCount: 0, insert: "x"), inlineCompletionApp: false, targetIsSpotlight: false) == .passAfter([.text("x")]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 1, insert: ""), inlineCompletionApp: false, targetIsSpotlight: false) == .swallow([.backspaces(1)]))
    }
    @Test func chunksRespectUTF16BoundaryAndWholeCharacters() {
        let twenty = String(repeating: "á", count: 20)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: twenty), inlineCompletionApp: false, targetIsSpotlight: false) == .swallow([.text(twenty)]))
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: twenty + "b"), inlineCompletionApp: false, targetIsSpotlight: false) == .swallow([.text(twenty), .text("b")]))
        let nineteen = String(repeating: "a", count: 19)
        #expect(OutputPlan.decision(for: .replace(deleteCount: 0, insert: nineteen + "😀b"), inlineCompletionApp: false, targetIsSpotlight: false) == .swallow([.text(nineteen), .text("😀b")]))
    }
}
