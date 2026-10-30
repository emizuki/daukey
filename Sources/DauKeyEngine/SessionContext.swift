/// Session settings that are not composition rules.
public struct SessionSettings: Sendable, Equatable {
    /// Capitalizes the first cased letter of a word that starts a sentence; applies from the next word.
    public var autoCapitalize: Bool

    public init(autoCapitalize: Bool = false) {
        self.autoCapitalize = autoCapitalize
    }
}

/// Text before the insertion point or the start of the selection, never including the selection.
///
/// Kept to at most `maxUTF16` UTF-16 units, cut at a `Character` boundary; a cut prefix no longer starts at the
/// document start.
public struct TextContext: Sendable, Equatable {
    public let prefix: String
    public let startsAtDocumentStart: Bool

    public static let maxUTF16 = 256

    public init(prefix: String, startsAtDocumentStart: Bool) {
        let kept = Self.boundedSuffix(of: prefix)
        let whole = kept.startIndex == prefix.startIndex
        self.prefix = whole ? prefix : String(kept)
        self.startsAtDocumentStart = startsAtDocumentStart && whole
    }

    /// Wraps a prefix that is already bounded; shares its storage.
    init(bounded prefix: String, startsAtDocumentStart: Bool) {
        self.prefix = prefix
        self.startsAtDocumentStart = startsAtDocumentStart
    }

    /// The longest suffix of `text` that has at most `maxUTF16` UTF-16 units and starts at a `Character` boundary.
    static func boundedSuffix(of text: String) -> Substring {
        guard text.utf16.count > maxUTF16 else { return text[...] }
        var start = text.endIndex
        var units = 0
        while start > text.startIndex {
            let previous = text.index(before: start)
            let width = text.utf16.distance(from: previous, to: start)
            if units + width > maxUTF16 { break }
            units += width
            start = previous
        }
        return text[start...]
    }
}

/// What a `TypingSession` expects before the caret, for checking a host sample against it.
public struct ContextProjection: Sendable, Equatable {
    /// The known end of the text before the caret; it starts at the document start only when that is known.
    public let context: TextContext
    /// UTF-16 units the caret moved since the last synchronization, or nil when that cannot be predicted.
    public let caretDeltaUTF16: Int?
    /// Whether the session owns text at the end of `context`: a word it may still edit and the breaks after it.
    public let hasOwnedSuffix: Bool
}

/// The known text before the caret, bounded to `TextContext.maxUTF16` UTF-16 units: text read from the host
/// followed by text the session tracked itself, which ends with the words the session owns.
///
/// This one string is the stored representation; edits change its end in place and a projection shares its storage.
/// The host part is counted in leading Unicode scalars so that forgetting it keeps the session's own evidence.
struct ContextBuffer: Sendable {
    private(set) var text = ""
    /// Whether `text` starts at the document start; false when the text before it is unknown.
    private(set) var startsAtDocumentStart = false
    private var utf16Count = 0
    /// Leading Unicode scalars of `text` read from the host.
    private var hostScalars = 0
    /// Trailing Unicode scalars of `text` the session tracked itself.
    private var trackedScalars = 0

    init() {}

    /// `host` from an accepted sample followed by `tracked`, the owned text the sample ended with.
    init(host: Substring, tracked: String, startsAtDocumentStart: Bool) {
        text = host + tracked
        self.startsAtDocumentStart = startsAtDocumentStart
        utf16Count = text.utf16.count
        hostScalars = host.unicodeScalars.count
        trackedScalars = tracked.unicodeScalars.count
        trimFront()
    }

    var context: TextContext { TextContext(bounded: text, startsAtDocumentStart: startsAtDocumentStart) }

    mutating func append(_ added: String) {
        text += added
        utf16Count += added.utf16.count
        trackedScalars += added.unicodeScalars.count
        trimFront()
    }

    /// Replaces `old`, which ends the text, with `new`, changing only the scalars after their common prefix.
    mutating func replaceEnd(_ old: String, with new: String) {
        let oldScalars = old.unicodeScalars
        let newScalars = new.unicodeScalars
        var oldIndex = oldScalars.startIndex
        var newIndex = newScalars.startIndex
        while oldIndex != oldScalars.endIndex, newIndex != newScalars.endIndex,
              oldScalars[oldIndex] == newScalars[newIndex] {
            oldScalars.formIndex(after: &oldIndex)
            newScalars.formIndex(after: &newIndex)
        }
        dropLastScalars(oldScalars.distance(from: oldIndex, to: oldScalars.endIndex))
        let added = newScalars[newIndex...]
        text.unicodeScalars.append(contentsOf: added)
        for scalar in added { utf16Count += scalar.utf16.count }
        trackedScalars += added.count
        trimFront()
    }

    /// Removes and returns the last character, or nil when nothing before the caret is known.
    mutating func removeLast() -> Character? {
        guard let character = text.popLast() else { return nil }
        utf16Count -= character.utf16.count
        let scalars = character.unicodeScalars.count
        let fromTracked = min(scalars, trackedScalars)
        trackedScalars -= fromTracked
        hostScalars = max(0, hostScalars - (scalars - fromTracked))
        return character
    }

    /// Forgets what was read from the host; text the session tracked itself stays.
    mutating func forgetHost() {
        startsAtDocumentStart = false
        guard hostScalars > 0 else { return }
        let end = text.unicodeScalars.index(text.startIndex, offsetBy: hostScalars)
        utf16Count -= text.utf16.distance(from: text.startIndex, to: end)
        text.removeSubrange(..<end)
        hostScalars = 0
    }

    private mutating func dropLastScalars(_ count: Int) {
        let count = min(count, hostScalars + trackedScalars)
        guard count > 0 else { return }
        let start = text.unicodeScalars.index(text.endIndex, offsetBy: -count)
        utf16Count -= text.utf16.distance(from: start, to: text.endIndex)
        text.removeSubrange(start...)
        let fromTracked = min(count, trackedScalars)
        trackedScalars -= fromTracked
        hostScalars -= count - fromTracked
    }

    /// Drops whole leading characters until the text fits the bound; the text then no longer starts at the document
    /// start.
    private mutating func trimFront() {
        guard utf16Count > TextContext.maxUTF16 else { return }
        var end = text.startIndex
        var dropped = 0
        while utf16Count - dropped > TextContext.maxUTF16, end < text.endIndex {
            let next = text.index(after: end)
            dropped += text.utf16.distance(from: end, to: next)
            end = next
        }
        let scalars = text.unicodeScalars.distance(from: text.startIndex, to: end)
        text.removeSubrange(..<end)
        utf16Count -= dropped
        let fromHost = min(scalars, hostScalars)
        hostScalars -= fromHost
        trackedScalars -= scalars - fromHost
        startsAtDocumentStart = false
    }
}

/// Where the caret is in its sentence, from the text before it.
enum SentencePosition: Equatable {
    case unknown
    case start
    case middle

    /// Reads `text`, which ends at the caret, backwards until a character decides the position.
    ///
    /// A newline, or `.`, `!`, `?` followed by whitespace, starts a sentence; a Tab gives no evidence. Opening quotes
    /// and brackets right before the caret are skipped. Abbreviations and numbers are not guessed. When no character
    /// decides, the position is the start only at a known document start.
    static func before(_ text: String, startsAtDocumentStart: Bool) -> SentencePosition {
        var sawWhitespace = false
        for character in text.reversed() {
            if character.isNewline { return .start }
            if character == "\t" { return .unknown }
            if character.isWhitespace {
                sawWhitespace = true
            } else if sawWhitespace || !opens(character) {
                return sawWhitespace && ".!?".contains(character) ? .start : .middle
            }
        }
        return startsAtDocumentStart ? .start : .unknown
    }

    private static func opens(_ character: Character) -> Bool {
        if character == "\"" || character == "'" { return true }
        switch character.unicodeScalars.first?.properties.generalCategory {
        case .openPunctuation?, .initialPunctuation?: return true
        default: return false
        }
    }
}
