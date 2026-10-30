import DauKeyEngine

/// Parses key scripts used by tests and the command-line driver.
///
/// `<` is Backspace, `|` is reset, `\N` is Return, `\T` is Tab, `\E` is endWord.
/// `\<`, `\|` and `\\` type the literal character. Every other character is typed as itself.
public enum Script {
    public static func events(_ script: String) -> [Event] {
        var events: [Event] = []
        var escaping = false
        for character in script {
            if escaping {
                escaping = false
                switch character {
                case "N": events.append(.char("\n"))
                case "T": events.append(.char("\t"))
                case "E": events.append(.endWord)
                default: events.append(.char(character))
                }
                continue
            }
            switch character {
            case "\\": escaping = true
            case "<": events.append(.backspace)
            case "|": events.append(.reset)
            default: events.append(.char(character))
            }
        }
        return events
    }
}

/// A simulated text field that applies session actions the way the keyboard hook does.
public struct Screen: Sendable, Equatable {
    public private(set) var text: [Character] = []

    public init() {}

    public var string: String { String(text) }

    public mutating func apply(_ event: Event, _ action: Action) {
        switch action {
        case .passThrough:
            deliver(event)
        case .replace(let deleteCount, let insert):
            text.removeLast(min(deleteCount, text.count))
            text.append(contentsOf: insert)
        case .replaceThenPass(let deleteCount, let insert):
            text.removeLast(min(deleteCount, text.count))
            text.append(contentsOf: insert)
            deliver(event)
        }
    }

    private mutating func deliver(_ event: Event) {
        switch event {
        case .char(let character): text.append(character)
        case .backspace: if !text.isEmpty { text.removeLast() }
        case .endWord, .reset: break
        }
    }
}

/// Types a key script into a fresh session.
public enum Typist {
    /// The simulated screen after typing `script`.
    public static func type(_ script: String, options: Options = Options()) -> String {
        var session = TypingSession(options: options)
        var screen = Screen()
        for event in Script.events(script) {
            screen.apply(event, session.handle(event))
        }
        return screen.string
    }
}
