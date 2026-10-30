import Foundation
import Testing
@testable import DauKeyEngine
import DauKeyScript

/// Deterministic random numbers (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Precomposed Vietnamese letters, built by Unicode composition rather than the engine's tables.
let vietnameseLetters: Set<Character> = {
    var letters: Set<Character> = ["đ", "Đ"]
    let marks = ["", "\u{301}", "\u{300}", "\u{309}", "\u{303}", "\u{323}"]
    for base in "aăâeêioôơuưyAĂÂEÊIOÔƠUƯY" {
        for mark in marks { letters.insert(Character((String(base) + mark).precomposedStringWithCanonicalMapping)) }
    }
    return letters
}()

/// Feeds events and checks spec §10 layer-3 invariants after each one. Records the first failure only.
///
/// Options are pinned per word: `setOptions` only changes the options of the next word. The checker keeps its own
/// expected options for the word being typed and for the word a Backspace can reopen, and judges every word by them,
/// never by the session's options for the next word.
struct Checker {
    /// Options for the next word.
    private(set) var options: Options
    /// The options the word being typed started with; nil while there is none.
    private var wordOptions: Options?
    /// The options of the finished word that deleting its breaks reopens.
    private var previousOptions: Options?
    private(set) var session: TypingSession
    private(set) var screen = Screen()
    private(set) var failure: String?
    private var baseline: [Character] = []
    private var typedInWord: [Character] = []
    /// The typed keys of the last finished word, so a reopened word keeps its own typing history.
    private var typedBeforeBreak: [Character] = []
    private var backspaceInWord = false
    private var shadow: TypingSession?
    private var trace = ""

    init(_ options: Options) {
        self.options = options
        self.session = TypingSession(options: options)
    }

    /// Spec §8: a new setting applies from the next word; the word being typed and the screen are left alone.
    mutating func setOptions(_ new: Options) {
        guard failure == nil else { return }
        trace += "{options}"
        let before = session
        let screenBefore = screen.text
        session.setOptions(new)
        shadow?.setOptions(new)
        options = new
        if session.keys != before.keys || session.display != before.display || session.mode != before.mode
            || session.previous != before.previous || session.breaksAfterPrevious != before.breaksAfterPrevious {
            fail("8: options change edited the session")
        }
        if session.activeOptions != wordOptions { fail("8: options change reached the word being typed") }
        if screen.text != screenBefore { fail("8: options change edited the screen") }
    }

    mutating func feed(_ event: Event) {
        guard failure == nil else { return }
        trace += Checker.describe(event)
        let before = session
        let screenBefore = screen.text
        let old = before.display
        let action = session.handle(event)
        let new = session.display

        switch action {
        case .replace(let count, let insert), .replaceThenPass(let count, let insert):
            if count > old.count { fail("1: deleteCount \(count) > \(old.count)") }
            if insert.unicodeScalars.contains(where: { (0x300...0x36F).contains($0.value) }) { fail("7: combining mark in \(insert)") }
            if !insert.allSatisfy(Checker.isAllowedOutput) { fail("7: unexpected character in \(insert)") }
        case .passThrough:
            break
        }
        screen.apply(event, action)

        // Invariant 2: a fresh session started at the last break gives the same results.
        if let running = shadow {
            if case .backspace = event, before.keys.isEmpty {
                shadow = nil
            } else {
                var copy = running
                let shadowAction = copy.handle(event)
                if shadowAction != action || copy.display != new { fail("2: differs from a fresh session") }
                shadow = copy
            }
        }

        switch event {
        case .char(let character):
            // Spec §4.3: a letter or a bracket ends a word holding only an escaped bracket. Such a word is Telex, since
            // a bracket is a break in VNI (§4.1), and the key is judged by the word's options, not the next word's.
            let endedBracketWord = before.mode == .composing && character.isASCII
                && (character.isLetter || "[]{}".contains(character))
                && before.keys.first.map({ "[]{}".contains($0) }) == true
                && Composer(options: wordOptions ?? options).compose(before.keys).elements.allSatisfy { $0.letter == nil }
            let wordCharacter = !session.keys.isEmpty
                && (session.keys == before.keys + [character] || (before.mode == .composing && session.mode == .literal))
            if endedBracketWord {
                // The escaped bracket stays on screen, and this character goes to a fresh session with the options for
                // the next word (spec §8), where it starts a word or, in VNI, is a break.
                var fresh = TypingSession(options: options)
                if fresh.handle(.char(character)) != action || fresh.display != new { fail("2: differs from a fresh session after a bracket word") }
                if session.previous != nil || session.breaksAfterPrevious != 0 { fail("6: a bracket word can be reopened") }
                shadow = fresh
                previousOptions = nil
                backspaceInWord = false
                if fresh.keys.isEmpty {
                    wordOptions = nil
                    baseline = screenBefore + [character]
                } else {
                    wordOptions = options
                    baseline = screenBefore
                    typedInWord = [character]
                }
                checkScreen(new)
            } else if wordCharacter {
                if (action == .passThrough) != (new == old + String(character)) { fail("3: passThrough mismatch") }
                if before.keys.isEmpty {
                    // A new word pins the options set for the next word.
                    wordOptions = options
                    baseline = screenBefore
                    typedInWord = []
                    backspaceInWord = false
                }
                typedInWord.append(character)
                checkScreen(new)
            } else {
                finishedWord(before: before, action: action, breakCharacter: character)
            }
        case .endWord:
            finishedWord(before: before, action: action, breakCharacter: nil)
        case .reset:
            if screen.text != screenBefore { fail("1: reset edited the screen") }
            if !(session.keys.isEmpty && session.previous == nil && session.breaksAfterPrevious == 0) { fail("6: reset did not clear the state") }
            wordOptions = nil
            previousOptions = nil
            baseline = screen.text
            shadow = TypingSession(options: options)
        case .backspace:
            if !before.keys.isEmpty {
                if (action == .passThrough) != (new == String(old.dropLast())) { fail("3: backspace passThrough mismatch") }
                if before.mode == .composing {
                    if session.keys.count >= before.keys.count { fail("4: backspace removed no key") }
                    let composer = Composer(options: wordOptions ?? options)
                    if composer.isCompletable(composer.compose(before.keys)), old.count - new.count != 1 {
                        fail("4: backspace removed \(old.count - new.count) characters from a completable word")
                    }
                }
                if session.keys.isEmpty { wordOptions = nil }
                backspaceInWord = true
                checkScreen(new)
            } else if !session.keys.isEmpty {
                if Array(screen.text.suffix(new.count)) != Array(new) { fail("6: reopened word is not on screen") }
                // The reopened word keeps the options it was typed with.
                wordOptions = previousOptions
                previousOptions = nil
                baseline = Array(screen.text.dropLast(new.count))
                typedInWord = typedBeforeBreak
                backspaceInWord = true
            } else {
                if screen.text != Array(screenBefore.dropLast()) { fail("1: backspace on committed text") }
                if session.previous == nil { previousOptions = nil }
                baseline = screen.text
            }
        }

        if session.activeOptions != (session.keys.isEmpty ? nil : wordOptions) {
            fail("8: the word uses \(String(describing: session.activeOptions)), not \(String(describing: wordOptions))")
        }
        guard let wordOptions, !session.keys.isEmpty else { return }
        let composition = Composer(options: wordOptions).compose(session.keys)
        if composition.tone != .none && Region.of(composition.elements) == nil { fail("8: tone without a vowel to carry it") }
        // Invariant 9: typing the session's keys into a fresh session with the word's options shows the same word.
        if session.mode == .composing {
            var replay = TypingSession(options: wordOptions)
            for key in session.keys { _ = replay.handle(.char(key)) }
            if replay.display != new { fail("9: replay of \(String(session.keys)) shows \(replay.display), not \(new)") }
        }
    }

    private mutating func checkScreen(_ display: String) {
        let expected = baseline + Array(display)
        if screen.text != expected { fail("1: screen \(String(screen.text)) != \(String(expected))") }
    }

    /// Spec §7.4. Only the segment boundary comes from the session; the last segment is judged with the test-side
    /// syllable list, independent of the composer's tables.
    private func expectsRestore(_ before: TypingSession, options: Options, breakCharacter: Character?) -> Bool {
        guard options.spelling == .checkAndRestore, before.mode == .composing,
              let breakCharacter, breakCharacter != "\n", breakCharacter != "\t" else { return false }
        let display = before.display
        guard display != String(before.keys), display.contains(where: { !$0.isASCII }) else { return false }
        // Every element renders as one character, so the last segment is the display's tail.
        let segmentLength = Composer(options: options).compose(before.keys).slots.count
        let last = String(display.suffix(segmentLength)).lowercased()
        // A nucleus vowel: a vowel letter other than the `u` of `qu` (spec §5.2, §7.4).
        let bases = last.map { String($0).decomposedStringWithCanonicalMapping.unicodeScalars.first.map(Character.init) ?? $0 }
        let hasNucleusVowel = bases.indices.contains { index in
            "aeiouy".contains(bases[index]) && !(bases[index] == "u" && index > 0 && bases[index - 1] == "q")
        }
        if !hasNucleusVowel { return !Syllables.prefixes(for: options).contains(last) }
        guard let parts = decompose(last) else { return true }
        return !Syllables.validKeys(for: options).contains("\(parts.letters)|\(parts.tone.rawValue)")
    }

    private mutating func finishedWord(before: TypingSession, action: Action, breakCharacter: Character?) {
        shadow = TypingSession(options: options)
        let breakText: [Character] = breakCharacter.map { [$0] } ?? []
        let soft = breakCharacter != nil && breakCharacter != "\n" && breakCharacter != "\t"
        guard !before.keys.isEmpty else {
            if screen.text != baseline + breakText { fail("1: break with no word changed the screen") }
            if !soft { previousOptions = nil }
            baseline = screen.text
            return
        }
        guard let finishedOptions = wordOptions else {
            fail("8: a word ended without the options it started with")
            return
        }
        wordOptions = nil
        typedBeforeBreak = typedInWord
        let restore = expectsRestore(before, options: finishedOptions, breakCharacter: breakCharacter)
        let restored: Bool
        if case .replaceThenPass = action { restored = true } else { restored = false }
        if restored != restore { fail("5: restore was \(restored), §7.4 says \(restore)") }
        if restore && !backspaceInWord && before.keys != typedInWord { fail("5: keys differ from the typed keys") }
        if restore && backspaceInWord {
            // Spec §10 invariant 5: the restored keys are a subsequence of the keys typed for this word.
            var rest = typedInWord[...]
            for key in before.keys {
                guard let found = rest.firstIndex(of: key) else {
                    fail("5: keys \(String(before.keys)) are not a subsequence of the typed \(String(typedInWord))")
                    break
                }
                rest = rest[rest.index(after: found)...]
            }
        }
        let committed: [Character] = restore ? before.keys : Array(before.display)
        if screen.text != baseline + committed + breakText { fail("1/5: committed text \(String(screen.text))") }
        // Invariant 6.
        var probe = session
        _ = probe.handle(.backspace)
        if soft && !restore {
            if probe.keys != before.keys || probe.mode != before.mode { fail("6: reopen did not restore the word") }
            if probe.activeOptions != finishedOptions { fail("6: the reopened word lost its options") }
        } else if !soft {
            if !probe.keys.isEmpty { fail("6: reopened across a hard break") }
        }
        previousOptions = soft ? finishedOptions : nil
        baseline = screen.text
    }

    /// Invariant 4, second half: a plainly appended letter followed by Backspace restores the exact state.
    mutating func probeLetterThenBackspace(_ letter: Character) {
        guard failure == nil else { return }
        var copy = session
        let old = copy.display
        let action = copy.handle(.char(letter))
        guard action == .passThrough, copy.display == old + String(letter), copy.mode == session.mode,
              copy.keys.count == session.keys.count + 1
        else { return }
        _ = copy.handle(.backspace)
        if copy.keys != session.keys || copy.display != session.display || copy.mode != session.mode
            || copy.activeOptions != session.activeOptions || copy.previous != session.previous
            || copy.breaksAfterPrevious != session.breaksAfterPrevious
            || copy.contextProjection != session.contextProjection {
            fail("4: letter then backspace changed the state")
        }
    }

    private mutating func fail(_ message: String) {
        if failure == nil { failure = "\(message) after \(trace) [\(options)]" }
    }

    static func describe(_ event: Event) -> String {
        switch event {
        case .char("\n"): return "\\N"
        case .char("\t"): return "\\T"
        case .char(let character): return String(character)
        case .backspace: return "<"
        case .endWord: return "\\E"
        case .reset: return "|"
        }
    }

    static func isAllowedOutput(_ character: Character) -> Bool {
        if character.isASCII { return character.isLetter || character.isNumber || "[]{}".contains(character) }
        return vietnameseLetters.contains(character)
    }
}

let telexAlphabet: [Event] = "aeiouysfrxjzwd[]bcghmnpqtAWSD".map { Event.char($0) }
    + [.char(" "), .char("."), .char("\n"), .backspace, .endWord, .reset]
let vniAlphabet: [Event] = "aeiouy0123456789bcdghmnpqtswAD".map { Event.char($0) }
    + [.char(" "), .char("."), .char("\n"), .backspace, .endWord, .reset]

var isLongRun: Bool { ProcessInfo.processInfo.environment["DAUKEY_LONG"] == "1" }

/// Depth-first enumeration of every event sequence up to `depth`, sharing prefixes.
private func enumerate(_ checker: Checker, alphabet: [Event], depth: Int, failure: inout String?) {
    guard depth > 0, failure == nil else { return }
    for event in alphabet {
        var next = checker
        next.feed(event)
        if let found = next.failure { failure = found; return }
        enumerate(next, alphabet: alphabet, depth: depth - 1, failure: &failure)
    }
}

private let englishWords = [
    "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "window", "system", "process", "function",
    "string", "return", "struct", "class", "import", "export", "default", "switch", "case", "while", "repeat",
    "guard", "async", "await", "error", "result", "value", "index", "keep", "deep", "meet", "photo", "data",
    "saw", "law", "worry", "tomorrow", "cheese", "things", "banana", "text", "tests", "address", "granddad",
]

@Suite struct InvariantTests {
    /// Spec §10 cost rule. Run every option combination to length 3 and each method/style pair to length 4.
    /// Long mode runs length 5.
    @Test(arguments: Options.all)
    func enumerationUpToLengthThree(_ options: Options) {
        var failure: String?
        let alphabet = options.inputMethod == .vni ? vniAlphabet : telexAlphabet
        enumerate(Checker(options), alphabet: alphabet, depth: isLongRun ? 5 : 3, failure: &failure)
        #expect(failure == nil, "\(failure ?? "")")
    }

    @Test(arguments: InputMethod.allCases.flatMap { method in
        ToneStyle.allCases.map { Options(inputMethod: method, toneStyle: $0) }
    })
    func enumerationLengthFour(_ options: Options) {
        var failure: String?
        let alphabet = options.inputMethod == .vni ? vniAlphabet : telexAlphabet
        enumerate(Checker(options), alphabet: alphabet, depth: 4, failure: &failure)
        #expect(failure == nil, "\(failure ?? "")")
    }

    @Test(arguments: InputMethod.allCases)
    func grammarDrivenPerturbations(_ method: InputMethod) {
        var corpus = GrammarCorpus(method: method)
        let seed = corpus.seed
        for index in 0..<GrammarCorpus.cases {
            let generated = corpus.next(index)
            let options = generated.options
            let events = generated.events
            var checker = Checker(options)
            for position in 0...events.count {
                if position == generated.switchAt { checker.setOptions(generated.nextOptions!) }
                guard position < events.count else { break }
                feedGrammarEvent(events[position], to: &checker)
            }
            if generated.unperturbed { feedGrammarEvent(.char(" "), to: &checker) }
            if let failure = checker.failure {
                Issue.record("case \(index) seed \(seed) [starting \(options)]: \(failure)")
                return
            }
            if generated.unperturbed {
                let expected = generated.words.map { word in
                    zip(word.letters, expectedText(word.syllable, style: options.toneStyle)).map { letter, rendered in
                        letter.isUppercase ? rendered.uppercased() : String(rendered)
                    }.joined()
                }.joined(separator: " ") + " "
                let actual = checker.screen.string
                if Array(actual.unicodeScalars) != Array(expected.unicodeScalars) {
                    Issue.record("case \(index) seed \(seed): \(String(generated.keys)) → \(actual), expected \(expected) [starting \(options)]")
                    return
                }
            }
        }
    }

    /// Sentences avoid open oa/oe/uy, so the expected text is the same in both tone styles.
    private static let sentences: [(telex: String, vni: String, text: String)] = [
        ("tooi yeeu tieengs vieetj", "to6i ye6u tie6ng1 vie65t", "tôi yêu tiếng việt"),
        ("chungs ta ddi hocj", "chu1ng ta d9i ho5c", "chúng ta đi học"),
        ("hoom nay trowif ddepj quas", "ho6m nay tro72i d9e5p qua1", "hôm nay trời đẹp quá"),
        ("nguowif ta nois rawngf", "nguo72i ta no1i ra8ng2", "người ta nói rằng"),
        ("cuoocj soongs vaanx tieeps tucj", "cuo65c so6ng1 va6n4 tie6p1 tu5c", "cuộc sống vẫn tiếp tục"),
        ("thuowr nhor tooi ddax ddocj sachs", "thuo73 nho3 to6i d9a4 d9o5c sa1ch", "thuở nhỏ tôi đã đọc sách"),
    ]

    @Test(arguments: Options.all)
    func textSamples(_ options: Options) {
        for sample in Self.sentences {
            var checker = Checker(options)
            let script = options.inputMethod == .vni ? sample.vni : sample.telex
            for event in Script.events(script + " ") { checker.feed(event) }
            #expect(checker.failure == nil, "\(checker.failure ?? "")")
            expectSameScalars(checker.screen.string, sample.text + " ", script)
        }
        var english = Checker(options)
        for event in Script.events(englishWords.joined(separator: " ") + " ") { english.feed(event) }
        #expect(english.failure == nil, "\(english.failure ?? "")")
    }

    @Test func optionChangesMidWord() {
        for first in Options.all {
            for second in InputMethod.allCases.map({ Options(inputMethod: $0) }) {
                var checker = Checker(first)
                for event in Script.events("tieeng") { checker.feed(event) }
                checker.setOptions(second)
                for event in Script.events("a1 nam ") { checker.feed(event) }
                #expect(checker.failure == nil, "\(checker.failure ?? "")")
            }
        }
    }

    /// The key after a word holding only an escaped bracket ends that word by the word's options (spec §4.3), then
    /// is typed with the options for the next word, where a bracket is a VNI break. The first script is long-run
    /// simple Telex case 1306858.
    @Test func escapedBracketWordEndsBeforeABreakOfTheNextOptions() {
        var checker = Checker(Options(inputMethod: .simpleTelex, toneStyle: .modern))
        for event in Script.events(")c <<<]]") { feedGrammarEvent(event, to: &checker) }
        checker.setOptions(Options(inputMethod: .vni, spelling: .off, allowForeignConsonants: true))
        for event in Script.events("}oamx") { feedGrammarEvent(event, to: &checker) }
        #expect(checker.failure == nil, "\(checker.failure ?? "")")
        expectSameScalars(checker.screen.string, "]}oamx")
        for method in [InputMethod.telex, .simpleTelex] {
            for escaped in ["[[", "]]", "{{", "}}"] {
                for bracket in "[]{}" {
                    var checker = Checker(Options(inputMethod: method))
                    for event in Script.events(escaped) { checker.feed(event) }
                    checker.setOptions(.vni)
                    for event in Script.events("\(bracket)<<a ") { checker.feed(event) }
                    #expect(checker.failure == nil, "\(method) \(escaped){vni}\(bracket): \(checker.failure ?? "")")
                }
            }
        }
    }

    @Test(arguments: Options.all)
    func longWordsOverflowReopenAndOverflowAgain(_ options: Options) {
        let long = String(repeating: "ba", count: 20)
        // The first script grows the reopened literal word; the second empties it, so the retyped word overflows again.
        for script in [long + " <" + "<<<<<" + long + "s ", long + " <" + String(repeating: "<", count: 40) + long + "s "] {
            var checker = Checker(options)
            for event in Script.events(script) { checker.feed(event) }
            #expect(checker.failure == nil, "\(script): \(checker.failure ?? "")")
        }
    }

    @Test func copiesAreIndependent() {
        var original = TypingSession()
        for character in "tieeng" { _ = original.handle(.char(character)) }
        var copy = original
        _ = copy.handle(.char("s"))
        _ = copy.handle(.char(" "))
        expectSameScalars(original.display, "tiêng")
        #expect(copy.keys.isEmpty)
        var a = TypingSession(), b = TypingSession(), alone = TypingSession()
        var interleaved: [Action] = []
        var solo: [Action] = []
        for character in "nguoiwf" {
            interleaved.append(a.handle(.char(character)))
            _ = b.handle(.char("x"))
            solo.append(alone.handle(.char(character)))
        }
        #expect(interleaved == solo)
    }
}

/// Keep the inverse probes after every generated event, including the expected-text check's final space.
private func feedGrammarEvent(_ event: Event, to checker: inout Checker) {
    checker.feed(event)
    // `n` is a plain letter; `d` can stroke a preceding `d` even where gating blocks everything else.
    checker.probeLetterThenBackspace("n")
    checker.probeLetterThenBackspace("d")
}

private func perturb(_ keys: inout [Character], _ random: inout SeededGenerator) {
    guard !keys.isEmpty else { return }
    let index = Int.random(in: 0..<keys.count, using: &random)
    switch Int.random(in: 0..<4, using: &random) {
    case 0:
        let key = keys.remove(at: index)
        keys.insert(key, at: Int.random(in: index...keys.count, using: &random))
    case 1:
        keys.insert(keys[index], at: index)
    case 2:
        keys.remove(at: index)
    default:
        let other = Int.random(in: 0..<keys.count, using: &random)
        keys.swapAt(index, other)
    }
}

/// One case of the grammar-driven corpus (spec §10 layer 3).
struct GrammarCase {
    /// The options the case starts with.
    let options: Options
    let words: [(syllable: Syllable, letters: [Character], keys: String)]
    /// The keys of the words before any inserted event.
    let keys: [Character]
    let events: [Event]
    /// Before which event the options change to `nextOptions`; `events.count` changes them after the last one.
    let switchAt: Int?
    let nextOptions: Options?
    /// No perturbation, inserted event, long-word prefix or option change: the expected text is known.
    let unperturbed: Bool
}

/// The grammar-driven cases of one input method, generated from its fixed seed in a fixed order, so every test that
/// walks the corpus sees the same cases.
struct GrammarCorpus {
    static var cases: Int { isLongRun ? 10_000_000 : 100_000 }

    let seed: UInt64
    private var random: SeededGenerator
    private let native: [Syllable]
    private let foreign: [Syllable]
    private let transformKeys: [Character]
    private let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private let symbols = Array(",;:!?()\"'-{}€")
    private let digits = Array("0123456789")
    private let symbolChoices: Int
    private let breaks: [Event] = [.char(" "), .char("."), .char("\n"), .char("\t"), .endWord, .reset]
    /// The option combinations of the method; case `index` starts with `combinations[index % combinations.count]`.
    let combinations: [Options]

    init(method: InputMethod) {
        seed = switch method {
        case .telex: 0xDA0C_E1
        case .simpleTelex: 0xDA0C_E3
        case .vni: 0xDA0C_E2
        }
        random = SeededGenerator(state: seed)
        // Valid dictionary syllables are a subset of the generated list (Task 13 checks every valid entry
        // against it), so the generated list is the pool for both corpora.
        // Exclude only the method's explicitly untypeable forms, before sampling, so every case runs.
        native = Syllables.all.filter { canonicalKeys($0.letters, tone: $0.tone, method: method) != nil }
        foreign = (method == .vni ? Syllables.foreignVNI : Syllables.foreignTelex)
            .filter { canonicalKeys($0.letters, tone: $0.tone, method: method) != nil }
        transformKeys = Array(method == .vni ? "0123456789" : "sfrxjzaeowd[]")
        symbolChoices = symbols.count + (method == .vni ? 0 : 1)
        combinations = Options.all.filter { $0.inputMethod == method }
    }

    /// The case after the previous one; `index` counts the cases from 0.
    mutating func next(_ index: Int) -> GrammarCase {
        let method = combinations[0].inputMethod
        let options = combinations[index % combinations.count]
        let syllables = options.allowForeignConsonants ? foreign : native
        var words: [(syllable: Syllable, letters: [Character], keys: String)] = []
        for _ in 0..<Int.random(in: 1...3, using: &random) {
            let syllable = syllables.randomElement(using: &random)!
            let form = Int.random(in: 0..<4, using: &random)
            let cased = syllable.letters.enumerated().map { position, letter -> Character in
                let upper = form == 3 || (form == 1 && position == 0)
                    || (form == 2 && Bool.random(using: &random))
                return upper ? Character(letter.uppercased()) : letter
            }
            var keys = canonicalKeys(String(cased), tone: syllable.tone, method: method)!
            if form == 3 {
                keys = String(keys.map { $0.isASCII && $0.isLetter ? Character($0.uppercased()) : $0 })
            }
            words.append((syllable, cased, keys))
        }
        let longWord = Int.random(in: 0..<100, using: &random) == 0
        if longWord {
            let length = Int.random(in: (TypingSession.maxKeys - 2)...(TypingSession.maxKeys + 2), using: &random)
            let prefix = (0..<(length - words[0].keys.count)).map { _ in
                letters[Int.random(in: 0..<26, using: &random)]
            }
            words[0].keys = String(prefix) + words[0].keys
        }
        var keys = Array(words.map(\.keys).joined(separator: " "))
        let perturbations = Int.random(in: 0...3, using: &random)
        for _ in 0..<perturbations { perturb(&keys, &random) }
        var events = keys.map { Event.char($0) }
        let extraCount = Int.random(in: 0...6, using: &random)
        var insertions: [(gap: Int, events: [Event])] = []
        for _ in 0..<extraCount {
            let extra: [Event]
            switch Int.random(in: 0..<6, using: &random) {
            case 0:
                extra = Array(repeating: .backspace, count: Int.random(in: 1...6, using: &random))
            case 1:
                extra = [breaks.randomElement(using: &random)!]
            case 2:
                extra = [.char(transformKeys.randomElement(using: &random)!)]
            case 3:
                extra = [.char(letters.randomElement(using: &random)!)]
            case 4:
                let choice = Int.random(in: 0..<symbolChoices, using: &random)
                extra = [.char(choice < symbols.count ? symbols[choice] : digits.randomElement(using: &random)!)]
            default:
                extra = [.char(" ")]
                    + Array(repeating: .backspace, count: Int.random(in: 1...3, using: &random))
                    + [.char(transformKeys.randomElement(using: &random)!)]
            }
            insertions.append((Int.random(in: 0...events.count, using: &random), extra))
        }
        // Every gap refers to the base sequence, so a later insertion cannot split an earlier run.
        insertions.sort { $0.gap > $1.gap }
        for insertion in insertions {
            events.insert(contentsOf: insertion.events, at: insertion.gap)
        }
        let switchAt = Int.random(in: 0..<20, using: &random) == 0
            ? Int.random(in: 0...events.count, using: &random) : nil
        let nextOptions = switchAt == nil ? nil : Options.all.randomElement(using: &random)
        return GrammarCase(
            options: options, words: words, keys: keys, events: events, switchAt: switchAt, nextOptions: nextOptions,
            unperturbed: perturbations == 0 && extraCount == 0 && !longWord && switchAt == nil
        )
    }
}
