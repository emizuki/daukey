/// Turns keyboard events into text edits for the word being typed and the one word before it that can be reopened.
public struct TypingSession: Sendable {
    /// Options for the next word; the current and previous words keep the options they started with.
    public private(set) var options: Options

    private var current: SessionWord?
    /// The word before the breaks typed after it; deleting all of those breaks reopens it.
    private(set) var previous: SessionWord?
    private(set) var breaksAfterPrevious = 0

    static let maxKeys = 32

    /// Why the current word ends.
    private enum FinishReason {
        /// A break character that keeps the word reopenable, such as Space or punctuation.
        case soft(Character)
        case newline
        case tab
        /// The word is dropped without a restore: navigation, shortcuts, or an escaped bracket barrier.
        case abandon
    }

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Applies to the next word; the word being typed keeps its options and is not rendered again.
    public mutating func setOptions(_ options: Options) {
        self.options = options
    }

    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .char(let character): return type(character)
        case .backspace: return backspace()
        case .endWord: return finish(.abandon)
        case .reset:
            current = nil
            previous = nil
            breaksAfterPrevious = 0
            return .passThrough
        }
    }

    // MARK: Read-only projections

    var keys: [Character] { current?.keys ?? [] }
    var display: String { current?.emittedText ?? "" }
    var mode: SessionWord.Mode { current?.mode ?? .composing }
    /// Options of the word being typed, if any.
    var activeOptions: Options? { current?.options }

    // MARK: Events

    private mutating func type(_ character: Character) -> Action {
        guard isWordCharacter(character) else { return finish(reason(for: character)) }
        var word = current ?? SessionWord(options: options)
        let old = word.emittedText
        if word.mode == .literal {
            word.keys.append(character)
            word.emittedText.append(character)
            current = word
            return .passThrough
        }
        let composer = word.composer
        if let first = word.keys.first, "[]{}".contains(first),
           composer.compose(word.keys).allSlots.allSatisfy({ $0.element.letter == nil }) {
            // Spec §4.3: a word holding only an escaped bracket ends here; it can never be reopened.
            _ = finish(.abandon)
            return type(character)
        }
        let keys = word.keys + [character]
        let composition = composer.compose(keys)
        if composition.lastKeyBroke { return finish(.soft(character)) }
        if keys.count > Self.maxKeys {
            var literal = SessionWord(options: word.options)
            literal.keys = Array(old) + [character]
            literal.mode = .literal
            literal.emittedText = old + String(character)
            current = literal
            return .passThrough
        }
        let new = composer.render(composition)
        word.keys = keys
        word.emittedText = new
        current = word
        return new == old + String(character) ? .passThrough : Self.replacement(old, new)
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

    private mutating func finish(_ reason: FinishReason) -> Action {
        var finished = current
        var action = Action.passThrough
        if case .soft = reason, let word = current, word.mode == .composing, word.options.spelling == .checkAndRestore {
            let typedKeys = String(word.keys)
            if Self.shouldRestore(word) {
                action = Self.replacementThenPass(word.emittedText, typedKeys)
                var restored = SessionWord(options: word.options)
                restored.keys = word.keys
                restored.mode = .literal
                restored.restored = true
                restored.originalKeys = word.keys.count
                restored.emittedText = typedKeys
                finished = restored
            }
        }
        current = nil
        switch reason {
        case .soft:
            if let finished {
                previous = finished
                breaksAfterPrevious = 1
            } else if previous != nil {
                breaksAfterPrevious += 1
            }
        case .newline, .tab, .abandon:
            previous = nil
            breaksAfterPrevious = 0
        }
        return action
    }

    /// Spec §7.4.
    private static func shouldRestore(_ word: SessionWord) -> Bool {
        let composer = word.composer
        let w = composer.compose(word.keys)
        guard word.emittedText != String(word.keys) else { return false }
        let hasMark = w.tone != .none || w.earlier.contains { $0.tone != .none }
            || w.allSlots.contains { ($0.element.letter?.modifier ?? .none) != .none }
        // The last segment is Vietnamese if it can still become a syllable and, once it has a vowel, is one.
        let lastIsVietnamese = composer.isCompletable(w) && (Region.of(w.elements) == nil || composer.isValid(w))
        return hasMark && !lastIsVietnamese
    }

    private mutating func backspace() -> Action {
        guard var word = current else {
            if breaksAfterPrevious > 0 {
                breaksAfterPrevious -= 1
                if breaksAfterPrevious == 0, let previous {
                    current = previous
                    self.previous = nil
                }
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
        } else {
            new = word.mode == .literal ? String(word.keys) : composer.display(word.keys)
            word.emittedText = new
            current = word
        }
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
