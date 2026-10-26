import DauKeyEngine

public enum OutputPlan {
    public static func decision(for action: Action, chromiumBrowser: Bool) -> Decision {
        switch action {
        case .passThrough: return .pass
        case let .replace(count, text): return .swallow(steps(count, text, chromiumBrowser: chromiumBrowser))
        case let .replaceThenPass(count, text): return .passAfter(steps(count, text, chromiumBrowser: chromiumBrowser))
        }
    }
    private static func steps(_ count: Int, _ text: String, chromiumBrowser: Bool) -> [OutputStep] {
        var result: [OutputStep] = []
        if count > 0 {
            // Replace any selected inline suggestion, then delete the placeholder and intended text.
            if chromiumBrowser { result.append(.text("\u{202F}")) }
            result.append(.backspaces(count + (chromiumBrowser ? 1 : 0)))
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
