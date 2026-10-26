import DauKeyEngine

public enum OutputPlan {
    public static func decision(for action: Action, inlineCompletionApp: Bool, targetIsSpotlight: Bool) -> Decision {
        switch action {
        case .passThrough: return .pass
        case let .replace(count, text):
            return .swallow(steps(count, text, inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: targetIsSpotlight))
        case let .replaceThenPass(count, text):
            return .passAfter(steps(count, text, inlineCompletionApp: inlineCompletionApp, targetIsSpotlight: targetIsSpotlight))
        }
    }
    private static func steps(_ count: Int, _ text: String, inlineCompletionApp: Bool, targetIsSpotlight: Bool) -> [OutputStep] {
        var result: [OutputStep] = []
        if count > 0 {
            if targetIsSpotlight {
                result.append(.selectBackward(count))
            } else {
                // Replace any selected inline suggestion, then delete the placeholder and intended text.
                if inlineCompletionApp { result.append(.text("\u{202F}")) }
                result.append(.backspaces(count + (inlineCompletionApp ? 1 : 0)))
            }
        }
        var start = text.startIndex
        var end = start
        var units = 0
        while end < text.endIndex {
            let next = text.index(after: end)
            let length = text[end..<next].utf16.count
            if units + length > 20 && end != start {
                result.append(.text(String(text[start..<end])))
                start = end
                units = 0
            }
            units += length
            end = next
        }
        if start != end { result.append(.text(String(text[start..<end]))) }
        return result
    }
}
