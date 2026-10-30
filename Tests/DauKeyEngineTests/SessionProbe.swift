import Testing
@testable import DauKeyEngine
import DauKeyScript

/// Drives a `TypingSession` against a simulated text field.
struct SessionProbe {
    var session: TypingSession
    private var screen = Screen()

    /// `initialText` is already in the field before the session starts; it is not fed to the session.
    init(options: Options = Options(), initialText: String = "") {
        session = TypingSession(options: options)
        for character in initialText {
            screen.apply(.char(character), .passThrough)
        }
    }

    var text: String { screen.string }

    /// Types every character of `text` as itself, including `<`.
    mutating func type(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for character in text {
            send(.char(character), sourceLocation: sourceLocation)
        }
    }

    /// Sends the events of a key script (`<` is Backspace, `\N` is Return).
    mutating func script(_ script: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for event in Script.events(script) {
            send(event, sourceLocation: sourceLocation)
        }
    }

    mutating func send(_ event: Event, sourceLocation: SourceLocation = #_sourceLocation) {
        let action = session.handle(event)
        switch action {
        case .passThrough:
            break
        case .replace(let deleteCount, _), .replaceThenPass(let deleteCount, _):
            // Screen clamps deletions, which would hide an edit reaching past the text.
            #expect(
                deleteCount >= 0 && deleteCount <= screen.text.count,
                "\(event) deletes \(deleteCount) of \(screen.text.count) characters",
                sourceLocation: sourceLocation
            )
        }
        screen.apply(event, action)
    }
}
