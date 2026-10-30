import Testing
@testable import DauKeyEngine
import DauKeyScript

/// Drives a `TypingSession` against a simulated text field.
///
/// After every event it checks the session's context projection against the field: the projected prefix is the end
/// of the field text, and a known caret delta equals the UTF-16 length change since the last synchronization.
struct SessionProbe {
    var session: TypingSession
    private var screen = Screen()
    /// UTF-16 length of the field text at the last accepted synchronization.
    private var anchorUTF16: Int?

    /// `initialText` is already in the field before the session starts; it is not fed to the session.
    /// `context`, if any, is synchronized into the session directly, as an accepted host sample would be.
    init(
        options: Options = Options(), initialText: String = "", settings: SessionSettings = SessionSettings(),
        context: TextContext? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        session = TypingSession(options: options, settings: settings)
        for character in initialText {
            screen.apply(.char(character), .passThrough)
        }
        if let context {
            synchronize(context, sourceLocation: sourceLocation)
        }
    }

    var text: String { screen.string }

    /// Synchronizes the session with `context`, as the runtime does for an accepted sample, and expects the session to
    /// accept it or not.
    mutating func synchronize(
        _ context: TextContext, accepted: Bool = true, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let result = session.synchronizeContext(context)
        #expect(result == accepted, "synchronizing \"\(context.prefix)\"", sourceLocation: sourceLocation)
        if result { anchorUTF16 = text.utf16.count }
    }

    /// Types every character of `text` as itself, including `<`.
    mutating func type(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for character in text {
            send(.char(character), sourceLocation: sourceLocation)
        }
    }

    /// Sends the events of a key script (`<` is Backspace, `|` is reset, `\N` is Return, `\T` is Tab).
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
        expectProjectionMatchesScreen(after: event, sourceLocation: sourceLocation)
    }

    private func expectProjectionMatchesScreen(after event: Event, sourceLocation: SourceLocation) {
        let projection = session.contextProjection
        let prefix = projection.context.prefix
        #expect(
            projection.context.startsAtDocumentStart ? text == prefix : text.hasSuffix(prefix),
            "after \(event) the projected prefix \"\(prefix)\" does not end the field \"\(text)\"",
            sourceLocation: sourceLocation
        )
        if let delta = projection.caretDeltaUTF16 {
            #expect(
                anchorUTF16.map { text.utf16.count - $0 } == delta,
                "after \(event) the caret delta \(delta) does not match the field",
                sourceLocation: sourceLocation
            )
        }
    }
}
