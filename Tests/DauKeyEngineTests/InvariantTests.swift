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
struct Checker {
    private(set) var options: Options
    private(set) var engine: Engine
    private(set) var screen = Screen()
    private(set) var failure: String?
    private var baseline: [Character] = []
    private var typedInWord: [Character] = []
    /// The typed keys of the last finished word, so a reopened word keeps its own typing history.
    private var typedBeforeBreak: [Character] = []
    private var backspaceInWord = false
    private var shadow: Engine?
    private var validKeys: Set<String>
    private var prefixes: Set<String>
    private var trace = ""

    init(_ options: Options) {
        self.options = options
        self.engine = Engine(options: options)
        self.validKeys = Syllables.validKeys(for: options)
        self.prefixes = Syllables.prefixes(for: options)
    }

    /// Spec §3: setting options is exactly `.reset` and leaves the screen alone.
    mutating func setOptions(_ new: Options) {
        guard failure == nil else { return }
        trace += "{options}"
        let screenBefore = screen.text
        engine.options = new
        options = new
        validKeys = Syllables.validKeys(for: new)
        prefixes = Syllables.prefixes(for: new)
        if !(engine.keys.isEmpty && engine.previous == nil && engine.breaksAfterPrevious == 0) { fail("8: options change did not reset") }
        if screen.text != screenBefore { fail("8: options change edited the screen") }
        baseline = screen.text
        shadow = Engine(options: new)
    }

    mutating func feed(_ event: Event) {
        guard failure == nil else { return }
        trace += Checker.describe(event)
        let before = engine
        let screenBefore = screen.text
        let old = before.display
        let action = engine.handle(event)
        let new = engine.display

        switch action {
        case .replace(let count, let insert), .replaceThenPass(let count, let insert):
            if count > old.count { fail("1: deleteCount \(count) > \(old.count)") }
            if insert.unicodeScalars.contains(where: { (0x300...0x36F).contains($0.value) }) { fail("7: combining mark in \(insert)") }
            if !insert.allSatisfy(Checker.isAllowedOutput) { fail("7: unexpected character in \(insert)") }
        case .passThrough:
            break
        }
        screen.apply(event, action)

        // Invariant 2: a fresh engine started at the last break gives the same results.
        if let running = shadow {
            if case .backspace = event, before.keys.isEmpty {
                shadow = nil
            } else {
                var copy = running
                let shadowAction = copy.handle(event)
                if shadowAction != action || copy.display != new { fail("2: differs from a fresh engine") }
                shadow = copy
            }
        }

        switch event {
        case .char(let character):
            let endedBracketWord = before.mode == .composing && engine.keys == [character]
                && before.keys.first.map({ "[]{}".contains($0) }) == true
                && Composer(options: options).compose(before.keys).elements.allSatisfy { $0.letter == nil }
            let wordCharacter = !engine.keys.isEmpty
                && (engine.keys == before.keys + [character] || (before.mode == .composing && engine.mode == .literal))
            if endedBracketWord {
                // Spec §4.3: the escaped bracket stays on screen and this character starts a fresh word.
                var fresh = Engine(options: options)
                if fresh.handle(.char(character)) != action || fresh.display != new { fail("2: differs from a fresh engine after a bracket word") }
                if engine.previous != nil || engine.breaksAfterPrevious != 0 { fail("6: a bracket word can be reopened") }
                shadow = fresh
                baseline = screenBefore
                typedInWord = [character]
                backspaceInWord = false
                checkScreen(new)
            } else if wordCharacter {
                if (action == .passThrough) != (new == old + String(character)) { fail("3: passThrough mismatch") }
                if before.keys.isEmpty {
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
            if !(engine.keys.isEmpty && engine.previous == nil && engine.breaksAfterPrevious == 0) { fail("6: reset did not clear the state") }
            baseline = screen.text
            shadow = Engine(options: options)
        case .backspace:
            if !before.keys.isEmpty {
                if (action == .passThrough) != (new == String(old.dropLast())) { fail("3: backspace passThrough mismatch") }
                if before.mode == .composing {
                    if engine.keys.count >= before.keys.count { fail("4: backspace removed no key") }
                    let composer = Composer(options: options)
                    if composer.isCompletable(composer.compose(before.keys)), old.count - new.count != 1 {
                        fail("4: backspace removed \(old.count - new.count) characters from a completable word")
                    }
                }
                backspaceInWord = true
                checkScreen(new)
            } else if !engine.keys.isEmpty {
                if Array(screen.text.suffix(new.count)) != Array(new) { fail("6: reopened word is not on screen") }
                baseline = Array(screen.text.dropLast(new.count))
                typedInWord = typedBeforeBreak
                backspaceInWord = true
            } else {
                if screen.text != Array(screenBefore.dropLast()) { fail("1: backspace on committed text") }
                baseline = screen.text
            }
        }

        let composition = Composer(options: options).compose(engine.keys)
        if composition.tone != .none && Region.of(composition.elements) == nil { fail("8: tone without a vowel to carry it") }
        // Invariant 9: typing the engine's keys into a fresh engine shows the same word.
        if engine.mode == .composing {
            var replay = Engine(options: options)
            for key in engine.keys { _ = replay.handle(.char(key)) }
            if replay.display != new { fail("9: replay of \(String(engine.keys)) shows \(replay.display), not \(new)") }
        }
    }

    private mutating func checkScreen(_ display: String) {
        let expected = baseline + Array(display)
        if screen.text != expected { fail("1: screen \(String(screen.text)) != \(String(expected))") }
    }

    /// Spec §7.4. Only the segment boundary comes from the engine; the last segment is judged with the test-side
    /// syllable list, independent of the engine's tables.
    private func expectsRestore(_ before: Engine, breakCharacter: Character?) -> Bool {
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
        if !hasNucleusVowel { return !prefixes.contains(last) }
        guard let parts = decompose(last) else { return true }
        return !validKeys.contains("\(parts.letters)|\(parts.tone.rawValue)")
    }

    private mutating func finishedWord(before: Engine, action: Action, breakCharacter: Character?) {
        shadow = Engine(options: options)
        let breakText: [Character] = breakCharacter.map { [$0] } ?? []
        guard !before.keys.isEmpty else {
            if screen.text != baseline + breakText { fail("1: break with no word changed the screen") }
            baseline = screen.text
            return
        }
        typedBeforeBreak = typedInWord
        let restore = expectsRestore(before, breakCharacter: breakCharacter)
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
        var probe = engine
        _ = probe.handle(.backspace)
        let soft = breakCharacter != nil && breakCharacter != "\n" && breakCharacter != "\t"
        if soft && !restore {
            if probe.keys != before.keys || probe.mode != before.mode { fail("6: reopen did not restore the word") }
        } else if !soft {
            if !probe.keys.isEmpty { fail("6: reopened across a hard break") }
        }
        baseline = screen.text
    }

    /// Invariant 4, second half: a plainly appended letter followed by Backspace restores the exact state.
    mutating func probeLetterThenBackspace(_ letter: Character) {
        guard failure == nil else { return }
        var copy = engine
        let old = copy.display
        let action = copy.handle(.char(letter))
        guard action == .passThrough, copy.display == old + String(letter), copy.mode == engine.mode,
              copy.keys.count == engine.keys.count + 1
        else { return }
        _ = copy.handle(.backspace)
        if copy.current != engine.current || copy.previous != engine.previous
            || copy.breaksAfterPrevious != engine.breaksAfterPrevious {
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

private let telexAlphabet: [Event] = "aeiouysfrxjzwd[]bcghmnpqtAWSD".map { Event.char($0) }
    + [.char(" "), .char("."), .char("\n"), .backspace, .endWord, .reset]
private let vniAlphabet: [Event] = "aeiouy0123456789bcdghmnpqtswAD".map { Event.char($0) }
    + [.char(" "), .char("."), .char("\n"), .backspace, .endWord, .reset]

private var isLongRun: Bool { ProcessInfo.processInfo.environment["DAUKEY_LONG"] == "1" }

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

@Suite(.serialized) struct InvariantTests {
    /// Spec §10 cost rule. A scratch run of the full length-4 matrix on this machine took 413 s (> 5 minutes),
    /// so all 24 combinations run up to length 3 and four combinations run length 4. Long mode runs length 5.
    @Test(arguments: Options.all)
    func enumerationUpToLengthThree(_ options: Options) {
        var failure: String?
        let alphabet = options.inputMethod == .telex ? telexAlphabet : vniAlphabet
        enumerate(Checker(options), alphabet: alphabet, depth: isLongRun ? 5 : 3, failure: &failure)
        #expect(failure == nil, "\(failure ?? "")")
    }

    @Test(arguments: [
        Options(), Options(toneStyle: .modern), Options(inputMethod: .vni), Options(inputMethod: .vni, toneStyle: .modern),
    ])
    func enumerationLengthFour(_ options: Options) {
        var failure: String?
        let alphabet = options.inputMethod == .telex ? telexAlphabet : vniAlphabet
        enumerate(Checker(options), alphabet: alphabet, depth: 4, failure: &failure)
        #expect(failure == nil, "\(failure ?? "")")
    }

    @Test(arguments: InputMethod.allCases)
    func grammarDrivenPerturbations(_ method: InputMethod) {
        let seed: UInt64 = method == .telex ? 0xDA0C_E1 : 0xDA0C_E2
        var random = SeededGenerator(state: seed)
        // Valid dictionary syllables are a subset of the generated list (Task 13 checks every valid entry
        // against it), so the generated list is the pool for both corpora.
        let syllables = Syllables.all
        let cases = isLongRun ? 10_000_000 : 100_000
        let combinations = Options.all.filter { $0.inputMethod == method }
        for index in 0..<cases {
            var options = combinations[index % combinations.count]
            let syllable = syllables[Int.random(in: 0..<syllables.count, using: &random)]
            guard var keys = canonicalKeys(syllable.letters, tone: syllable.tone, method: method).map({ Array($0) }) else { continue }
            let perturbations = Int.random(in: 0...3, using: &random)
            for _ in 0..<perturbations { perturb(&keys, &random) }
            var events = keys.map { Event.char($0) }
            let extraCount = Int.random(in: 0...2, using: &random)
            for _ in 0..<extraCount {
                let extra: [Event] = [.backspace, .char(" "), .char("."), .endWord, .reset, .char("\n")]
                events.insert(extra.randomElement(using: &random)!, at: Int.random(in: 0...events.count, using: &random))
            }
            let switchAt: Int? = Int.random(in: 0..<20, using: &random) == 0 ? Int.random(in: 0...events.count, using: &random) : nil
            var checker = Checker(options)
            for (position, event) in events.enumerated() {
                if position == switchAt {
                    options = combinations[(index + 1) % combinations.count]
                    checker.setOptions(options)
                }
                checker.feed(event)
                // `n` is a plain letter; `d` can stroke a preceding `d` even where gating blocks everything else.
                checker.probeLetterThenBackspace("n")
                checker.probeLetterThenBackspace("d")
            }
            if perturbations == 0 && extraCount == 0 && switchAt == nil {
                checker.feed(.char(" "))
                let expected = expectedText(syllable, style: options.toneStyle) + " "
                let actual = checker.screen.string
                if Array(actual.unicodeScalars) != Array(expected.unicodeScalars) {
                    Issue.record("case \(index) seed \(seed): \(String(keys)) → \(actual), expected \(expected) [\(options)]")
                    return
                }
            }
            if let failure = checker.failure {
                Issue.record("case \(index) seed \(seed): \(failure)")
                return
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
            let script = options.inputMethod == .telex ? sample.telex : sample.vni
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
            for second in [Options(), Options(inputMethod: .vni)] {
                var checker = Checker(first)
                for event in Script.events("tieeng") { checker.feed(event) }
                checker.setOptions(second)
                for event in Script.events("a1 nam ") { checker.feed(event) }
                #expect(checker.failure == nil, "\(checker.failure ?? "")")
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
        var original = Engine()
        for character in "tieeng" { _ = original.handle(.char(character)) }
        var copy = original
        _ = copy.handle(.char("s"))
        _ = copy.handle(.char(" "))
        expectSameScalars(original.display, "tiêng")
        #expect(copy.keys.isEmpty)
        var a = Engine(), b = Engine(), alone = Engine()
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
