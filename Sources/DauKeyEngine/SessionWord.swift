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
    /// The text the session has emitted for this word, which is what the screen shows for it.
    var emittedText = ""

    init(options: Options) {
        self.options = options
    }

    var composer: Composer { Composer(options: options) }
}
