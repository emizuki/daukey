/// One word owned by a `TypingSession`: the keys the user typed, how they compose, and the text on screen.
struct SessionWord: Equatable, Sendable {
    enum Mode: Sendable, Equatable {
        case composing
        case literal
    }

    var keys: [Character] = []
    var mode: Mode = .composing
    /// Restored to its typed keys at a word end (spec §4 case b).
    var restored = false
    /// How many of the keys present at the restore are still there (spec §4); keys after them were typed after a reopen.
    var originalKeys = 0
    /// Composition options fixed when the word started; later setting changes apply to the next word.
    let options: Options
    /// Whether the word's first cased letter is shown uppercase; fixed when the word started and kept when
    /// the word is reopened, restored, or turns literal. The keys stay as typed.
    let capitalized: Bool
    /// The text the session has emitted for this word, which is what the screen shows for it.
    var emittedText = ""

    init(options: Options, capitalized: Bool) {
        self.options = options
        self.capitalized = capitalized
    }

    var composer: Composer { Composer(options: options) }

    /// The word's casing applied to `text`, a render or the typed keys of this word.
    func cased(_ text: String) -> String {
        guard capitalized, let first = text.firstIndex(where: \.isCased) else { return text }
        var result = text
        result.replaceSubrange(first...first, with: text[first].uppercased())
        return result
    }
}
