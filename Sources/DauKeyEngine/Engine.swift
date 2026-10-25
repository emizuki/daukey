enum Mode: Sendable, Equatable {
    case composing
    case literal
}

struct Word: Equatable, Sendable {
    var keys: [Character] = []
    var mode: Mode = .composing
    /// Restored to its typed keys at a word end (spec §4 case b).
    var restored = false
    /// How many of the keys present at the restore are still there (spec §4); keys after them were typed after a reopen.
    var originalKeys = 0
}

/// Turns keyboard events into text edits (spec §3–§4).
public struct Engine: Sendable {
    public var options: Options {
        didSet { reset() }
    }

    private(set) var current = Word()
    private(set) var previous: Word?
    private(set) var breaksAfterPrevious = 0

    static let maxKeys = 32

    public init(options: Options = Options()) {
        self.options = options
    }

    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .char(let character): return type(character)
        case .backspace: return backspace()
        case .endWord: return breakWord(with: nil, old: display)
        case .reset:
            reset()
            return .passThrough
        }
    }

    // MARK: Test-visible state

    var display: String { display(of: current) }
    var keys: [Character] { current.keys }
    var mode: Mode { current.mode }

    private var composer: Composer { Composer(options: options) }

    private func display(of word: Word) -> String {
        word.mode == .literal ? String(word.keys) : composer.display(word.keys)
    }

    // MARK: Events

    private mutating func type(_ character: Character) -> Action {
        let old = display
        guard isWordCharacter(character) else { return breakWord(with: character, old: old) }
        if current.mode == .literal {
            current.keys.append(character)
            return .passThrough
        }
        if let first = current.keys.first, "[]{}".contains(first),
           composer.compose(current.keys).allSlots.allSatisfy({ $0.element.letter == nil }) {
            // Spec §4.3: a word holding only an escaped bracket ends here; it can never be reopened.
            reset()
            return type(character)
        }
        let keys = current.keys + [character]
        let composition = composer.compose(keys)
        if composition.lastKeyBroke { return breakWord(with: character, old: old) }
        if keys.count > Self.maxKeys {
            current = Word(keys: Array(old) + [character], mode: .literal)
            return .passThrough
        }
        current.keys = keys
        let new = composer.render(composition)
        return new == old + String(character) ? .passThrough : replacement(old, new)
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        if character.isLetter { return true }
        switch options.inputMethod {
        case .telex: return character == "[" || character == "]" || character == "{" || character == "}"
        case .vni: return character.isNumber && !current.keys.isEmpty
        }
    }

    /// Ends the current word for a break character, or for `endWord` when `character` is nil.
    private mutating func breakWord(with character: Character?, old: String) -> Action {
        let hard = character == nil || character == "\n" || character == "\t"
        let (finished, action) = finishWord(old: old, restoring: !hard)
        if hard {
            previous = nil
            breaksAfterPrevious = 0
        } else if let finished {
            previous = finished
            breaksAfterPrevious = 1
        } else if previous != nil {
            breaksAfterPrevious += 1
        }
        return action
    }

    private mutating func finishWord(old: String, restoring: Bool) -> (Word?, Action) {
        guard !current.keys.isEmpty else { return (nil, .passThrough) }
        var finished = current
        var action = Action.passThrough
        if restoring && current.mode == .composing && options.spelling == .checkAndRestore {
            let typedKeys = String(current.keys)
            if shouldRestore(composer.compose(current.keys), display: old, typedKeys: typedKeys) {
                let change = Self.diff(old, typedKeys)
                action = .replaceThenPass(deleteCount: change.deleteCount, insert: change.insert)
                finished = Word(keys: current.keys, mode: .literal, restored: true, originalKeys: current.keys.count)
            }
        }
        current = Word()
        return (finished, action)
    }

    /// Spec §7.4.
    private func shouldRestore(_ w: Composition, display: String, typedKeys: String) -> Bool {
        guard display != typedKeys else { return false }
        let hasMark = w.tone != .none || w.earlier.contains { $0.tone != .none }
            || w.allSlots.contains { ($0.element.letter?.modifier ?? .none) != .none }
        // The last segment is Vietnamese if it can still become a syllable and, once it has a vowel, is one.
        let lastIsVietnamese = composer.isCompletable(w) && (Region.of(w.elements) == nil || composer.isValid(w))
        return hasMark && !lastIsVietnamese
    }

    private mutating func backspace() -> Action {
        guard !current.keys.isEmpty else {
            if breaksAfterPrevious > 0 {
                breaksAfterPrevious -= 1
                if breaksAfterPrevious == 0, let word = previous {
                    current = word
                    previous = nil
                }
            }
            return .passThrough
        }
        let old = display
        switch current.mode {
        case .literal:
            // Spec §4: only a Backspace into the keys present at the restore can return the word to composing.
            let removesOriginal = current.restored && current.keys.count == current.originalKeys
            current.keys.removeLast()
            if removesOriginal { current.originalKeys = current.keys.count }
            if removesOriginal, composer.display(current.keys) == String(current.keys) {
                current.mode = .composing
                current.restored = false
                current.originalKeys = 0
            }
        case .composing:
            current.keys = composer.keysAfterBackspace(current.keys)
        }
        if current.keys.isEmpty { current = Word() }
        let new = display
        return new == String(old.dropLast()) ? .passThrough : replacement(old, new)
    }

    private mutating func reset() {
        current = Word()
        previous = nil
        breaksAfterPrevious = 0
    }

    private func replacement(_ old: String, _ new: String) -> Action {
        let change = Self.diff(old, new)
        return .replace(deleteCount: change.deleteCount, insert: change.insert)
    }

    /// Characters to delete from the end of `a` and text to type so that it reads `b` (spec §4.3).
    static func diff(_ a: String, _ b: String) -> (deleteCount: Int, insert: String) {
        let old = Array(a)
        let new = Array(b)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        return (old.count - prefix, String(new[prefix...]))
    }
}
