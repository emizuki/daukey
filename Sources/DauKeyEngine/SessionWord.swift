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
    /// The macro token this word continues, as it was when the word started; a reopened word gets it back.
    let token: MacroToken

    init(options: Options, capitalized: Bool, token: MacroToken) {
        self.options = options
        self.capitalized = capitalized
        self.token = token
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

/// The text typed since the last whitespace that a macro may replace, and the rules it is matched with.
///
/// Holds the characters before the word being typed; the word itself is read from the word when the token ends.
struct MacroToken: Sendable, Equatable {
    /// The rules when the token started; rule changes apply from the next token.
    let rules: RuleTables
    /// False when the token continues host text that does not end with whitespace, which it does not own.
    let eligible: Bool
    /// Whether the token holds an excluded word or an expansion; it is then never matched.
    private(set) var suppressed: Bool
    /// Characters in the token.
    private(set) var count = 0
    /// The token's characters while it can still match: eligible, not suppressed, no longer than the longest trigger,
    /// and holding exactly `count` characters. Once nil it stays nil, even if Backspace shortens the token.
    private(set) var text: String? = ""

    init(rules: RuleTables, eligible: Bool, suppressed: Bool = false) {
        self.rules = rules
        self.eligible = eligible
        self.suppressed = suppressed
        if !eligible || suppressed { text = nil }
    }

    /// The token followed by `added`; `suppressing` when `added` is an excluded word or joins the text before it.
    func appending(_ added: some StringProtocol, suppressing: Bool = false) -> MacroToken {
        var token = self
        token.count += added.count
        token.suppressed = suppressed || suppressing
        token.text = nil
        if let text, !token.suppressed, token.count <= rules.maxTriggerLength {
            let joined = text + added
            // Text that joins the character before it no longer holds one character per character added.
            if joined.count == token.count { token.text = joined }
        }
        return token
    }

    /// The token without its last character, or nil when nothing is left of it.
    func droppingLast() -> MacroToken? {
        guard count > 1 else { return nil }
        var token = self
        token.count -= 1
        _ = token.text?.popLast()
        return token
    }

    /// The replacement for the token ending with `word`, the text shown for the word being typed, if a macro
    /// matches; also returns the replaced text.
    func match(endingWith word: String) -> (text: String, replacement: String)? {
        guard let text, count + word.count <= rules.maxTriggerLength else { return nil }
        let candidate = text + word
        return rules.replacement(for: candidate).map { (candidate, $0) }
    }
}
