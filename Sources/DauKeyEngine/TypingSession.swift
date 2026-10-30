/// Turns keyboard events into text edits for the word being typed and the one word before it that can be reopened.
///
/// It also tracks a bounded view of the text before the caret, for sentence casing and for checking host
/// samples against what the session expects, and the token a macro may replace.
public struct TypingSession: Sendable {
    /// Options for the next word; the current and previous words keep the options they started with.
    public private(set) var options: Options
    /// Settings for the next word; the current and previous words keep the casing they started with.
    public private(set) var settings: SessionSettings
    /// Rules for the next token; a token keeps the rules it started with.
    public private(set) var rules: RuleTables

    private var current: SessionWord?
    /// The word before the breaks typed after it; deleting all of those breaks reopens it.
    private(set) var previous: SessionWord?
    /// The break characters typed after `previous`; empty when there is no previous word.
    private var breaks = ""
    /// The empty start of each token among `breaks` that begins after whitespace, oldest first. Rebuilding such a
    /// token after a Backspace starts from it, so the token keeps the rules it started with.
    private var breakTokens: [MacroToken] = []
    /// The macro token ending at the caret when no word is being typed; nil after whitespace or before any text.
    /// A word being typed holds the token it continues instead.
    private var token: MacroToken?
    /// The known text before the caret, ending with `previous`, `breaks` and `current`.
    private var context = ContextBuffer()
    /// UTF-16 units the caret moved since the last synchronization; nil without one or once unpredictable.
    private var caretDelta: Int?

    static let maxKeys = 32

    /// Why the current word ends.
    private enum FinishReason {
        /// A break character that keeps the word reopenable, such as Space or punctuation.
        case soft(Character)
        case newline
        case tab
        /// The word is dropped without a restore: navigation, shortcuts, or an escaped bracket barrier.
        case abandon

        /// The character typed after the word, or nil when the word is dropped.
        var delimiter: Character? {
            switch self {
            case .soft(let character): character
            case .newline: "\n"
            case .tab: "\t"
            case .abandon: nil
            }
        }

        /// Whether the token is tried against the macros: at Space, Return, and Unicode punctuation.
        var triesMacro: Bool {
            switch self {
            case .soft(let character): character == " " || character.isPunctuation
            case .newline: true
            case .tab, .abandon: false
            }
        }
    }

    public init(
        options: Options = Options(), settings: SessionSettings = SessionSettings(), rules: RuleTables = RuleTables()
    ) {
        self.options = options
        self.settings = settings
        self.rules = rules
    }

    /// Applies to the next word; the word being typed keeps its options and is not rendered again.
    public mutating func setOptions(_ options: Options) {
        self.options = options
    }

    /// Applies to the next word; the word being typed keeps its casing and is not rendered again.
    public mutating func setSettings(_ settings: SessionSettings) {
        self.settings = settings
    }

    /// Applies to the next token; the token being typed, and the one of a word that is reopened, keep their rules.
    public mutating func setRules(_ rules: RuleTables) {
        self.rules = rules
    }

    /// `bypassMacro` skips the macro this event would expand; it applies to this event only.
    public mutating func handle(_ event: Event, bypassMacro: Bool = false) -> Action {
        switch event {
        case .char(let character):
            let action = type(character, bypassMacro: bypassMacro)
            boundFrame()
            return action
        case .backspace: return backspace()
        case .endWord: return finish(.abandon, bypassMacro: bypassMacro)
        case .reset:
            current = nil
            previous = nil
            breaks = ""
            breakTokens = []
            token = nil
            context = ContextBuffer()
            caretDelta = nil
            return .passThrough
        }
    }

    // MARK: Context

    /// The text the session expects before the caret and how far the caret moved since the last synchronization.
    /// Built from stored state; the prefix shares the stored text's storage.
    public var contextProjection: ContextProjection {
        ContextProjection(context: context.context, caretDeltaUTF16: caretDelta, hasOwnedSuffix: hasOwnedText)
    }

    /// Whether `context` ends with the text the session owns, so `synchronizeContext` would accept it.
    public func canSynchronizeContext(_ context: TextContext) -> Bool {
        ownedCharacterCount(endingAt: context.prefix) != nil
    }

    /// Takes the host text before the owned text from `context` and restarts the caret delta from it.
    ///
    /// The word, its frame, and its casing are kept. Returns false, changing nothing, when `context` does not end
    /// with the owned text; the caller then resets the session.
    public mutating func synchronizeContext(_ context: TextContext) -> Bool {
        guard let owned = ownedCharacterCount(endingAt: context.prefix) else { return false }
        // The owned part keeps the session's own scalars, which may differ from the sample's equivalent ones.
        self.context = ContextBuffer(
            host: context.prefix.dropLast(owned),
            tracked: (previous?.emittedText ?? "") + breaks + (current?.emittedText ?? ""),
            startsAtDocumentStart: context.startsAtDocumentStart
        )
        caretDelta = 0
        return true
    }

    /// Drops what was read from the host and the caret delta; the words and the breaks the session tracked stay.
    public mutating func invalidateContext() {
        context.forgetHost()
        caretDelta = nil
    }

    /// Whether the session owns text before the caret: the previous word with its breaks, or the current word.
    private var hasOwnedText: Bool { previous != nil || current != nil }

    /// How many characters at the end of `prefix` are the owned text, or nil when `prefix` does not end with it.
    /// Characters compare by canonical equivalence.
    private func ownedCharacterCount(endingAt prefix: String) -> Int? {
        var sample = prefix.reversed().makeIterator()
        var count = 0
        func matches(_ part: String) -> Bool {
            for character in part.reversed() {
                guard sample.next() == character else { return false }
                count += 1
            }
            return true
        }
        guard matches(current?.emittedText ?? ""), matches(breaks), matches(previous?.emittedText ?? "") else {
            return nil
        }
        return count
    }

    /// Ends ownership of the previous word once it and the text after it no longer fit the tracked bound.
    private mutating func boundFrame() {
        guard let previous else { return }
        let units = previous.emittedText.utf16.count + breaks.utf16.count + (current?.emittedText.utf16.count ?? 0)
        if units > TextContext.maxUTF16 { releasePrevious() }
    }

    /// Ends the reopen frame of the previous word; its text stays known context.
    private mutating func releasePrevious() {
        previous = nil
        breaks = ""
        breakTokens = []
    }

    private mutating func moveCaret(by units: Int) {
        guard let delta = caretDelta else { return }
        let (moved, overflow) = delta.addingReportingOverflow(units)
        caretDelta = overflow ? nil : moved
    }

    private mutating func replaceText(_ old: String, with new: String) {
        context.replaceEnd(old, with: new)
        moveCaret(by: new.utf16.count - old.utf16.count)
    }

    /// Records text typed at the caret.
    private mutating func appendText(_ text: String) {
        context.append(text)
        moveCaret(by: text.utf16.count)
    }

    // MARK: Read-only projections

    var keys: [Character] { current?.keys ?? [] }
    var display: String { current?.emittedText ?? "" }
    var mode: SessionWord.Mode { current?.mode ?? .composing }
    /// Options of the word being typed, if any.
    var activeOptions: Options? { current?.options }
    /// Breaks typed after the previous word; deleting them all reopens it.
    var breaksAfterPrevious: Int { breaks.count }

    // MARK: Events

    private mutating func type(_ character: Character, bypassMacro: Bool) -> Action {
        guard isWordCharacter(character) else { return finish(reason(for: character), bypassMacro: bypassMacro) }
        var word = current ?? newWord()
        let old = word.emittedText
        if word.mode == .literal {
            word.keys.append(character)
            return emit(word, replacing: old, with: word.cased(String(word.keys)), typed: character)
        }
        let composer = word.composer
        if let first = word.keys.first, "[]{}".contains(first),
           composer.compose(word.keys).allSlots.allSatisfy({ $0.element.letter == nil }) {
            // Spec §4.3: a word holding only an escaped bracket ends here; it can never be reopened.
            _ = finish(.abandon, bypassMacro: bypassMacro)
            return type(character, bypassMacro: bypassMacro)
        }
        let keys = word.keys + [character]
        let composition = composer.compose(keys)
        if composition.lastKeyBroke { return finish(.soft(character), bypassMacro: bypassMacro) }
        if keys.count > Self.maxKeys {
            // The keys of a literal word are the uncased render so far; casing stays a projection.
            var literal = SessionWord(options: word.options, capitalized: word.capitalized, token: word.token)
            literal.keys = Array(composer.display(word.keys)) + [character]
            literal.mode = .literal
            return emit(literal, replacing: old, with: literal.cased(String(literal.keys)), typed: character)
        }
        word.keys = keys
        return emit(word, replacing: old, with: word.cased(composer.render(composition)), typed: character)
    }

    /// Stores `word` showing `new` as the current word and returns the edit from `old` after typing `character`.
    private mutating func emit(_ word: SessionWord, replacing old: String, with new: String, typed character: Character) -> Action {
        var word = word
        word.emittedText = new
        current = word
        // The word holds the token it continues.
        token = nil
        replaceText(old, with: new)
        return new == old + String(character) ? .passThrough : Self.replacement(old, new)
    }

    /// A word starting at the caret, capitalized when auto-capitalize is on and the caret starts a sentence.
    private func newWord() -> SessionWord {
        let capitalized = settings.autoCapitalize
            && SentencePosition.before(context.text, startsAtDocumentStart: context.startsAtDocumentStart) == .start
        return SessionWord(options: options, capitalized: capitalized, token: token ?? startToken())
    }

    /// A token starting at the caret with the current rules. It can match only after whitespace or where nothing
    /// before the caret is known; it does not own a continuation of known text.
    private func startToken() -> MacroToken {
        MacroToken(rules: rules, eligible: context.text.last?.isWhitespace ?? true)
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        if character.isLetter { return true }
        switch (current?.options ?? options).inputMethod {
        case .telex, .simpleTelex: return character == "[" || character == "]" || character == "{" || character == "}"
        case .vni: return character.isNumber && current != nil
        }
    }

    private func reason(for character: Character) -> FinishReason {
        switch character {
        case "\n": .newline
        case "\t": .tab
        default: .soft(character)
        }
    }

    private mutating func finish(_ reason: FinishReason, bypassMacro: Bool) -> Action {
        guard let delimiter = reason.delimiter else {
            // The word and its token are dropped; the text stays as known context.
            current = nil
            token = nil
            releasePrevious()
            return .passThrough
        }
        // At a boundary an exclusion comes first, then a macro, then the spelling restore.
        var finished = current
        var action = Action.passThrough
        let excluded = current.map(isExcluded) ?? false
        if let word = current, excluded {
            // The keys as typed, without the word's casing.
            let raw = String(word.keys)
            action = edit(word.emittedText, to: raw)
            finished?.emittedText = raw
        } else if reason.triesMacro, !bypassMacro, let tokenBefore = current?.token ?? token,
                  let match = tokenBefore.match(endingWith: current?.emittedText ?? "") {
            action = edit(match.text, to: match.replacement)
            finished = expansion(of: match.replacement, in: tokenBefore)
        } else if case .soft = reason, let word = current, word.mode == .composing,
                  word.options.spelling == .checkAndRestore, Self.shouldRestore(word) {
            // The restored keys keep the word's casing.
            var restored = SessionWord(options: word.options, capitalized: word.capitalized, token: word.token)
            restored.keys = word.keys
            restored.mode = .literal
            restored.restored = true
            restored.originalKeys = word.keys.count
            restored.emittedText = word.cased(String(word.keys))
            action = edit(word.emittedText, to: restored.emittedText)
            finished = restored
        }
        // The token goes on past punctuation and other breaks; whitespace ends it.
        var next: MacroToken?
        var started: MacroToken?
        if !delimiter.isWhitespace {
            let continued = finished.map { $0.token.appending($0.emittedText, suppressing: excluded) } ?? token
            let base = continued ?? startToken()
            if continued == nil { started = base }
            next = base.appending(String(delimiter))
        }
        current = nil
        token = next
        if case .soft = reason {
            if let finished {
                previous = finished
                breaks = String(delimiter)
                breakTokens = []
            } else if previous != nil {
                breaks.append(delimiter)
                if let started { breakTokens.append(started) }
            }
        } else {
            // Return and Tab never reopen the word (baseline); the text stays as known context.
            releasePrevious()
        }
        appendText(String(delimiter))
        return action
    }

    /// Replaces `old`, which ends the text, with `new` before the original key goes through.
    private mutating func edit(_ old: String, to new: String) -> Action {
        guard new != old else { return .passThrough }
        replaceText(old, with: new)
        return Self.replacementThenPass(old, new)
    }

    /// Whether the rules of the word's token leave the word as typed.
    private func isExcluded(_ word: SessionWord) -> Bool {
        word.token.rules.excludes(String(word.keys))
    }

    /// The word an expansion leaves at the caret: literal text, the end of `replacement` bounded like the context,
    /// in a token that never matches again.
    private func expansion(of replacement: String, in token: MacroToken) -> SessionWord {
        var word = SessionWord(
            options: current?.options ?? options, capitalized: false,
            token: MacroToken(rules: token.rules, eligible: token.eligible, suppressed: true)
        )
        word.keys = Array(TextContext.boundedSuffix(of: replacement))
        word.mode = .literal
        word.emittedText = String(word.keys)
        return word
    }

    /// The token after `previous` and the remaining `breaks`, rebuilt from where it started: the token the previous
    /// word continued, or the start of a token that begins after whitespace among the breaks.
    private func tokenAfterBreaks(of previous: SessionWord) -> MacroToken? {
        if let space = breaks.lastIndex(where: \.isWhitespace) {
            let rest = breaks[breaks.index(after: space)...]
            return rest.isEmpty ? nil : breakTokens.last?.appending(rest)
        }
        return previous.token.appending(previous.emittedText, suppressing: isExcluded(previous)).appending(breaks)
    }

    /// Spec §7.4.
    private static func shouldRestore(_ word: SessionWord) -> Bool {
        let composer = word.composer
        let w = composer.compose(word.keys)
        guard composer.render(w) != String(word.keys) else { return false }
        let hasMark = w.tone != .none || w.earlier.contains { $0.tone != .none }
            || w.allSlots.contains { ($0.element.letter?.modifier ?? .none) != .none }
        // The last segment is Vietnamese if it can still become a syllable and, once it has a vowel, is one.
        let lastIsVietnamese = composer.isCompletable(w) && (Region.of(w.elements) == nil || composer.isValid(w))
        return hasMark && !lastIsVietnamese
    }

    private mutating func backspace() -> Action {
        guard var word = current else {
            if let previous, let removed = breaks.popLast() {
                _ = context.removeLast()
                moveCaret(by: -removed.utf16.count)
                if !removed.isWhitespace, breaks.last?.isWhitespace == true {
                    // The token that began after that whitespace is gone.
                    breakTokens.removeLast()
                }
                if breaks.isEmpty {
                    current = previous
                    self.previous = nil
                    token = nil
                } else if removed.isWhitespace || token?.text == nil {
                    token = tokenAfterBreaks(of: previous)
                } else {
                    token = token?.droppingLast()
                }
            } else {
                if let removed = context.removeLast() {
                    moveCaret(by: -removed.utf16.count)
                } else if !context.startsAtDocumentStart {
                    // The deleted character is unknown, so the caret can no longer be predicted.
                    caretDelta = nil
                }
                token = token?.droppingLast()
            }
            return .passThrough
        }
        let old = word.emittedText
        let composer = word.composer
        switch word.mode {
        case .literal:
            // Spec §4: only a Backspace into the keys present at the restore can return the word to composing.
            let removesOriginal = word.restored && word.keys.count == word.originalKeys
            word.keys.removeLast()
            if removesOriginal { word.originalKeys = word.keys.count }
            if removesOriginal, composer.display(word.keys) == String(word.keys) {
                word.mode = .composing
                word.restored = false
                word.originalKeys = 0
            }
        case .composing:
            word.keys = composer.keysAfterBackspace(word.keys)
        }
        let new: String
        if word.keys.isEmpty {
            current = nil
            new = ""
            // A token that started with this word is gone with it.
            token = word.token.count > 0 ? word.token : nil
        } else {
            new = word.cased(word.mode == .literal ? String(word.keys) : composer.display(word.keys))
            word.emittedText = new
            current = word
        }
        replaceText(old, with: new)
        return new == String(old.dropLast()) ? .passThrough : Self.replacement(old, new)
    }

    private static func replacement(_ old: String, _ new: String) -> Action {
        let change = diff(old, new)
        return .replace(deleteCount: change.deleteCount, insert: change.insert)
    }

    private static func replacementThenPass(_ old: String, _ new: String) -> Action {
        let change = diff(old, new)
        return .replaceThenPass(deleteCount: change.deleteCount, insert: change.insert)
    }

    /// Characters to delete from the end of `a` and text to type so that it reads `b` (spec §4.3).
    private static func diff(_ a: String, _ b: String) -> (deleteCount: Int, insert: String) {
        let old = Array(a)
        let new = Array(b)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        return (old.count - prefix, String(new[prefix...]))
    }
}
