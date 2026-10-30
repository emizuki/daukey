import Testing
@testable import DauKeyEngine
import DauKeyScript

/// A configuration the session invariants run in: composition options, session settings, rule tables and a host
/// context synchronized before the first key.
struct SessionScenario: Sendable, CustomTestStringConvertible {
    /// Host text in the field that the session did not type.
    static let hostPrefix = "host prefix: "

    let name: String
    var options: Options
    let settings: SessionSettings
    let rules: RuleTables
    let context: TextContext?
    /// The rows `rules` is built from, kept so oracles never read the compiled tables back.
    let macros: [MacroRule]
    let exclusions: [String]
    /// Key scripts that reach the scenario's features; spliced into generated scripts and typed before enumerations.
    let words: [String]

    init(
        _ name: String, settings: SessionSettings = SessionSettings(), macros: [MacroRule] = [],
        exclusions: [String] = [], context: TextContext? = nil, words: [String] = []
    ) {
        self.name = name
        options = Options()
        self.settings = settings
        rules = RuleTables(macros: macros, exclusions: exclusions)
        self.context = context
        self.macros = macros
        self.exclusions = exclusions
        self.words = words
    }

    /// The field before the first key: the synchronized prefix, or host text the session does not know.
    var initialText: String { context?.prefix ?? Self.hostPrefix }

    func with(_ options: Options) -> SessionScenario {
        var copy = self
        copy.options = options
        return copy
    }

    var testDescription: String { "\(name) \(options)" }
}

extension SessionScenario {
    static let autoCapitalize = SessionSettings(autoCapitalize: true)
    static let casingWords = ["xin.", "xin. ", "toi\\N", "Toi", "chao ban.<"]

    static let baseline = SessionScenario("baseline")
    static let unknownCasing = SessionScenario("unknown casing", settings: autoCapitalize, words: casingWords)
    static let documentStartCasing = SessionScenario(
        "document-start casing", settings: autoCapitalize,
        context: TextContext(prefix: "", startsAtDocumentStart: true), words: casingWords
    )
    static let midSentenceCasing = SessionScenario(
        "mid-sentence casing", settings: autoCapitalize,
        context: TextContext(prefix: hostPrefix, startsAtDocumentStart: true), words: casingWords
    )
    static let exclusions = SessionScenario(
        "exclusions", exclusions: ["been", "test", "boss", "too"],
        words: ["been", "test", "boss", "too", "tooi", "toon", "Been", "TOO"]
    )
    static let macros = SessionScenario(
        "macros",
        macros: [MacroRule(trigger: "vn", replacement: "Việt Nam"), MacroRule(trigger: "tôi", replacement: "nội dung")],
        words: ["vn", "VN", "tooi", "to6i", "TOOI"]
    )
    static let collision = SessionScenario(
        "collision", macros: [MacroRule(trigger: "been", replacement: "expanded")], exclusions: ["been"],
        words: ["been", "Been", "BEEN", "bee"]
    )

    static let features = [unknownCasing, documentStartCasing, midSentenceCasing, exclusions, macros, collision]
    static let all = [baseline] + features
}

/// Feeds events to a session in a scenario and checks the session against a field it edits. Records the first
/// failure only. Every oracle is computed test-side from the field and the scenario's rows:
///
/// - owned suffix: a synthetic edit deletes only text typed since the last abandon, reset, Return or Tab, never host
///   text, and the field always ends with the text the session owns;
/// - frame: the projected context is exactly the field after the last point the session can know, bounded to
///   `TextContext.maxUTF16` units, and the caret delta is the field's UTF-16 change since the last synchronization;
/// - abandon: Escape and reset never edit the field, and Tab edits only an excluded word;
/// - casing: with auto-capitalize on, a twin session with it off types the same field except for the first cased
///   letter of words that start a sentence by the test-side rule.
struct SessionChecker {
    let scenario: SessionScenario
    private(set) var session: TypingSession
    private(set) var screen = Screen()
    private(set) var failure: String?
    /// The ownership epoch of each field character; host text is -1.
    private var tags: [Int]
    private var epoch = 0
    /// The field index where the text the session can know begins, and whether that is the document start.
    private var knownStart: Int
    private var documentStart = false
    /// The field's UTF-16 length at the last synchronization, while the caret delta is predictable.
    private var anchorUTF16: Int?
    private var fieldUTF16: Int
    private var twin: TypingSession?
    private var twinScreen = Screen()
    /// The field index where each word typed so far starts, and whether it starts a sentence.
    private var wordStarts: [Int: Bool] = [:]
    private let exclusionKeys: Set<String>
    private let replacementCharacters: Set<Character>
    private var trace = ""

    init(_ scenario: SessionScenario) {
        self.scenario = scenario
        session = TypingSession(options: scenario.options, settings: scenario.settings, rules: scenario.rules)
        for character in scenario.initialText { screen.apply(.char(character), .passThrough) }
        tags = Array(repeating: -1, count: screen.text.count)
        knownStart = screen.text.count
        fieldUTF16 = scenario.initialText.utf16.count
        if scenario.settings.autoCapitalize {
            twin = TypingSession(options: scenario.options, rules: scenario.rules)
            twinScreen = screen
        }
        exclusionKeys = Set(scenario.exclusions.map { $0.lowercased() })
        replacementCharacters = Set(scenario.macros.flatMap { Array($0.replacement) })
        if let context = scenario.context { synchronize(context, twinContext: context) }
    }

    mutating func setOptions(_ options: Options) {
        guard failure == nil else { return }
        trace += "{options}"
        session.setOptions(options)
        twin?.setOptions(options)
    }

    /// Synchronizes with the whole field as a sample read at the caret would, when it fits one sample.
    mutating func synchronizeWithField() {
        guard failure == nil, fieldUTF16 <= TextContext.maxUTF16 else { return }
        synchronize(
            TextContext(prefix: screen.string, startsAtDocumentStart: true),
            twinContext: TextContext(prefix: twinScreen.string, startsAtDocumentStart: true)
        )
    }

    private mutating func synchronize(_ context: TextContext, twinContext: TextContext) {
        trace += "{sync}"
        guard session.synchronizeContext(context) else {
            fail("owned: the session rejected a sample ending with its text")
            return
        }
        if twin?.synchronizeContext(twinContext) == false { fail("casing: the twin rejected its field") }
        knownStart = screen.text.count - context.prefix.count
        documentStart = context.startsAtDocumentStart
        anchorUTF16 = fieldUTF16
        checkFrame()
    }

    mutating func feed(_ event: Event) {
        guard failure == nil else { return }
        trace += Checker.describe(event)
        let fieldBefore = screen.text.count
        let knownBefore = knownStart
        let documentStartBefore = documentStart
        let wordBefore = session.display
        let action = session.handle(event)

        switch action {
        case .replace(let count, let insert), .replaceThenPass(let count, let insert):
            if count > tags.count {
                fail("owned: deletes \(count) of \(tags.count) characters")
            } else if tags.suffix(count).contains(where: { $0 != epoch }) {
                fail("owned: deletes text the session does not own")
            }
            if insert.unicodeScalars.contains(where: { (0x300...0x36F).contains($0.value) }) {
                fail("7: combining mark in \(insert)")
            }
            if !insert.allSatisfy({ Checker.isAllowedOutput($0) || replacementCharacters.contains($0) }) {
                fail("7: unexpected character in \(insert)")
            }
        case .passThrough:
            break
        }
        switch event {
        case .endWord, .reset:
            if action != .passThrough { fail("abandon: \(Checker.describe(event)) edited the field") }
        case .char("\t"):
            if case .replaceThenPass(let count, let insert) = action,
               !exclusionKeys.contains((String(wordBefore.dropLast(count)) + insert).lowercased()) {
                fail("abandon: Tab edited a word that is not excluded")
            }
        default:
            break
        }
        apply(event, action)

        switch event {
        case .reset:
            knownStart = screen.text.count
            documentStart = false
            anchorUTF16 = nil
        case .backspace where knownBefore == fieldBefore && !documentStartBefore:
            // Nothing before the caret was known, so the deleted character and the caret are unknown.
            anchorUTF16 = nil
        default:
            break
        }
        knownStart = min(knownStart, screen.text.count)
        var units = screen.text[knownStart...].reduce(0) { $0 + $1.utf16.count }
        while units > TextContext.maxUTF16 {
            units -= screen.text[knownStart].utf16.count
            knownStart += 1
            documentStart = false
        }
        checkFrame()
        if twin != nil { checkCasing(event, knownBefore: knownBefore, documentStartBefore: documentStartBefore) }
    }

    private mutating func apply(_ event: Event, _ action: Action) {
        screen.apply(event, action)
        var delivers = true
        switch action {
        case .passThrough:
            break
        case .replace(let count, let insert):
            delivers = false
            tags.removeLast(min(count, tags.count))
            tags += Array(repeating: epoch, count: insert.count)
        case .replaceThenPass(let count, let insert):
            tags.removeLast(min(count, tags.count))
            tags += Array(repeating: epoch, count: insert.count)
        }
        if delivers {
            switch event {
            case .char: tags.append(epoch)
            case .backspace: if !tags.isEmpty { tags.removeLast() }
            case .endWord, .reset: break
            }
        }
        switch event {
        case .endWord, .reset, .char("\n"), .char("\t"): epoch += 1
        default: break
        }
        if tags.count != screen.text.count { fail("owned: tags lost track of the field") }
        fieldUTF16 = screen.string.utf16.count
    }

    private mutating func checkFrame() {
        let projection = session.contextProjection
        let known = screen.text[knownStart...]
        if !projection.context.prefix.elementsEqual(known) || projection.context.startsAtDocumentStart != documentStart {
            fail(
                "frame: the session expects \"\(projection.context.prefix)\" (start \(projection.context.startsAtDocumentStart)), "
                    + "the field has \"\(String(known))\" (start \(documentStart))"
            )
            return
        }
        let delta = anchorUTF16.map { fieldUTF16 - $0 }
        if projection.caretDeltaUTF16 != delta {
            fail("frame: caret delta \(String(describing: projection.caretDeltaUTF16)), expected \(String(describing: delta))")
            return
        }
        guard fieldUTF16 <= TextContext.maxUTF16 else { return }
        if !session.canSynchronizeContext(TextContext(prefix: screen.string, startsAtDocumentStart: true)) {
            fail("owned: the field does not end with the text the session owns")
        } else if projection.hasOwnedSuffix, !screen.text.isEmpty {
            var altered = screen.text
            altered[altered.count - 1] = "\u{1}"
            if session.canSynchronizeContext(TextContext(prefix: String(altered), startsAtDocumentStart: true)) {
                fail("owned: a field with another last character still matches the owned text")
            }
        }
    }

    private mutating func checkCasing(_ event: Event, knownBefore: Int, documentStartBefore: Bool) {
        guard var twin else { return }
        twinScreen.apply(event, twin.handle(event))
        self.twin = twin
        let count = screen.text.count
        if wordStarts.keys.contains(where: { $0 >= count }) { wordStarts = wordStarts.filter { $0.key < count } }
        let wordStart = count - session.display.count
        if case .char = event, !session.keys.isEmpty, wordStarts[wordStart] == nil {
            // A new word: its casing follows the known text before it when it started.
            let known = knownBefore <= wordStart ? screen.text[knownBefore..<wordStart] : []
            wordStarts[wordStart] = scenario.settings.autoCapitalize
                && Self.startsSentence(known, documentStart: documentStartBefore && knownBefore <= wordStart)
        }
        guard twinScreen.text.count == count else {
            fail("casing: the field has \(count) characters, the twin \(twinScreen.text.count)")
            return
        }
        var capitalizes = false
        var casedSeen = false
        for index in 0..<count {
            if let start = wordStarts[index] {
                capitalizes = start
                casedSeen = false
            }
            let shown = screen.text[index]
            let twinShown = twinScreen.text[index]
            if shown != twinShown, !(capitalizes && !casedSeen && String(shown) == twinShown.uppercased()) {
                fail("casing: \"\(shown)\" at \(index) where the uncapitalized twin has \"\(twinShown)\"")
                return
            }
            if twinShown.isCased { casedSeen = true }
        }
        guard !session.keys.isEmpty else { return }
        guard let capitalized = wordStarts[wordStart] else {
            fail("casing: no start recorded for the word at \(wordStart)")
            return
        }
        if capitalized, let first = session.display.first(where: \.isCased), String(first) != first.uppercased() {
            fail("casing: the word at \(wordStart) starts a sentence but shows \(session.display)")
        }
    }

    /// Spec §7, written from its text rather than from `SentencePosition`: a word starts a sentence after a newline,
    /// or after `.`, `!` or `?` and whitespace, skipping opening quotes and brackets right before it. A Tab gives no
    /// evidence; with nothing deciding, only a known document start does.
    static func startsSentence(_ known: ArraySlice<Character>, documentStart: Bool) -> Bool {
        var index = known.endIndex
        while index > known.startIndex, opens(known[index - 1]) { index -= 1 }
        var sawWhitespace = false
        while index > known.startIndex, known[index - 1].isWhitespace {
            if known[index - 1].isNewline { return true }
            if known[index - 1] == "\t" { return false }
            sawWhitespace = true
            index -= 1
        }
        guard index > known.startIndex else { return documentStart }
        return sawWhitespace && ".!?".contains(known[index - 1])
    }

    private static func opens(_ character: Character) -> Bool {
        if character == "\"" || character == "'" { return true }
        let category = character.unicodeScalars.first?.properties.generalCategory
        return category == .openPunctuation || category == .initialPunctuation
    }

    private mutating func fail(_ message: String) {
        if failure == nil { failure = "\(message) after \(trace) [\(scenario.name) \(scenario.options)]" }
    }
}

/// One step of a generated script.
enum SessionStep {
    case event(Event)
    case options(Options)
    case synchronize
}

extension SessionChecker {
    mutating func run(_ steps: [SessionStep]) {
        for step in steps {
            switch step {
            case .event(let event): feed(event)
            case .options(let options): setOptions(options)
            case .synchronize: synchronizeWithField()
            }
        }
    }

    mutating func type(_ script: String) {
        for event in Script.events(script) { feed(event) }
    }
}

/// Depth-first enumeration of every event sequence up to `depth`, sharing prefixes.
private func enumerateSession(_ checker: SessionChecker, alphabet: [Event], depth: Int, failure: inout String?) {
    guard depth > 0, failure == nil else { return }
    for event in alphabet {
        var next = checker
        next.feed(event)
        if let found = next.failure {
            failure = found
            return
        }
        enumerateSession(next, alphabet: alphabet, depth: depth - 1, failure: &failure)
    }
}

/// The generated scripts of spec §10: an enumeration per option combination, or the grammar corpus of a method.
enum GeneratedScripts: Sendable, CustomTestStringConvertible {
    case enumeration(Int)
    case grammar(InputMethod)

    static let all: [GeneratedScripts] = Options.all.indices.map(enumeration) + InputMethod.allCases.map(grammar)

    var testDescription: String {
        switch self {
        case .enumeration(let index): "enumeration \(Options.all[index])"
        case .grammar(let method): "grammar \(method)"
        }
    }
}

/// A fixed transition: the field after typing `script` in `scenario`, derived by hand from the spec.
struct SessionTransition: Sendable, CustomTestStringConvertible {
    let scenario: SessionScenario
    let script: String
    let field: String

    init(_ scenario: SessionScenario, _ options: Options, _ script: String, _ field: String) {
        self.scenario = scenario.with(options)
        self.script = script
        self.field = field
    }

    /// Telex with the default options.
    init(_ scenario: SessionScenario, _ script: String, _ field: String) {
        self.init(scenario, Options(), script, field)
    }

    var testDescription: String { "\(scenario.name) \(scenario.options.inputMethod) \(script.prefix(40))" }
}

@Suite struct SessionInvariantTests {
    static let host = SessionScenario.hostPrefix

    /// Baseline scripts (spec §10) in the baseline scenario and, in turn, in each feature scenario: the session edits
    /// only the suffix it owns, its frame is the field's known end, and casing changes only sentence starts.
    @Test(arguments: GeneratedScripts.all)
    func generatedScriptsRespectOwnedSuffix(_ scripts: GeneratedScripts) {
        let features = SessionScenario.features
        switch scripts {
        case .enumeration(let index):
            let options = Options.all[index]
            let alphabet = options.inputMethod == .vni ? vniAlphabet : telexAlphabet
            let depth = isLongRun ? 5 : 3
            var failure: String?
            enumerateSession(
                SessionChecker(SessionScenario.baseline.with(options)), alphabet: alphabet, depth: depth, failure: &failure
            )
            #expect(failure == nil, "\(failure ?? "")")
            // A Latin square over (method, style) x (spelling, foreign): each feature meets every method and spelling.
            let scenario = features[(index + index / 6) % features.count].with(options)
            let word = scenario.words[(index / 6) % scenario.words.count]
            var start = SessionChecker(scenario)
            start.type(word)
            failure = start.failure
            enumerateSession(start, alphabet: alphabet, depth: depth, failure: &failure)
            #expect(failure == nil, "\(failure ?? "")")
        case .grammar(let method):
            var corpus = GrammarCorpus(method: method)
            // Feature splices draw from their own generator, so the corpus stays the baseline one.
            var splices = SeededGenerator(state: corpus.seed ^ 0x5E55_10E5)
            let delimiters: [Event] = [.char(" "), .char("."), .char(","), .char("\n"), .char("\t"), .endWord, .reset]
            for index in 0..<GrammarCorpus.cases {
                let generated = corpus.next(index)
                var steps = generated.events.map(SessionStep.event)
                if let switchAt = generated.switchAt { steps.insert(.options(generated.nextOptions!), at: switchAt) }

                var baseline = SessionChecker(SessionScenario.baseline.with(generated.options))
                baseline.run(steps)
                if let failure = baseline.failure {
                    Issue.record("case \(index) seed \(corpus.seed): \(failure)")
                    return
                }

                let scenario = features[(index / corpus.combinations.count) % features.count].with(generated.options)
                for _ in 0..<Int.random(in: 1...2, using: &splices) {
                    let word = scenario.words.randomElement(using: &splices)!
                    let spliced = Script.events(word).map(SessionStep.event)
                        + [.event(delimiters.randomElement(using: &splices)!)]
                    steps.insert(contentsOf: spliced, at: Int.random(in: 0...steps.count, using: &splices))
                }
                if Int.random(in: 0..<4, using: &splices) == 0 {
                    steps.insert(.synchronize, at: Int.random(in: 0...steps.count, using: &splices))
                }
                steps.append(.event(.char(" ")))
                var feature = SessionChecker(scenario)
                feature.run(steps)
                if let failure = feature.failure {
                    Issue.record("case \(index) seed \(corpus.seed): \(failure)")
                    return
                }
            }
        }
    }

    /// Spec §8: a session is a value. Two copies from `vn` with `vn -> Việt Nam` go their own ways.
    @Test(arguments: Options.all)
    func copiedSessionsRemainIndependent(_ options: Options) {
        let scenario = SessionScenario.macros.with(options)
        var original = SessionChecker(scenario)
        original.type("vn")
        var expanded = original
        var abandoned = original
        expanded.type(" ")
        abandoned.feed(.endWord)
        expectSameScalars(expanded.screen.string, Self.host + "Việt Nam ")
        expectSameScalars(abandoned.screen.string, Self.host + "vn")
        // Interleaved: each copy keeps its own word, token and frame. The abandoned `vn` stays; a new token after the
        // space expands.
        for (first, second) in zip("vn ", " vn") {
            expanded.feed(.char(first))
            abandoned.feed(.char(second))
        }
        abandoned.type(" ")
        expectSameScalars(expanded.screen.string, Self.host + "Việt Nam Việt Nam ")
        expectSameScalars(abandoned.screen.string, Self.host + "vn Việt Nam ")
        expectSameScalars(original.screen.string, Self.host + "vn")
        original.type("\\N")
        expectSameScalars(original.screen.string, Self.host + "Việt Nam\n")
        for checker in [original, expanded, abandoned] {
            #expect(checker.failure == nil, "\(checker.failure ?? "")")
        }

        // Generated: copies split at a random point of a corpus case each take a different rest; each must end as a
        // session that typed its whole script alone.
        var corpus = GrammarCorpus(method: options.inputMethod)
        var random = SeededGenerator(state: corpus.seed ^ 0xC0_B1E5)
        var previous: [Event] = Script.events("vn tooi been ")
        let index = Options.all.firstIndex(of: options)!
        for round in 0..<(isLongRun ? 20_000 : 200) {
            let events = corpus.next(round).events
            let scenario = SessionScenario.all[(round + index) % SessionScenario.all.count].with(options)
            let split = Int.random(in: 0...events.count, using: &random)
            var prefix = SessionChecker(scenario)
            for event in events[..<split] { prefix.feed(event) }
            var first = prefix
            var second = prefix
            let rest = Array(events[split...])
            for position in 0..<max(rest.count, previous.count) {
                if position < rest.count { first.feed(rest[position]) }
                if position < previous.count { second.feed(previous[position]) }
            }
            var aloneFirst = SessionChecker(scenario)
            for event in events { aloneFirst.feed(event) }
            var aloneSecond = SessionChecker(scenario)
            for event in events[..<split] + previous { aloneSecond.feed(event) }
            for (copy, alone) in [(first, aloneFirst), (second, aloneSecond)] {
                #expect(copy.failure == nil, "\(copy.failure ?? "")")
                if copy.screen != alone.screen || copy.session.contextProjection != alone.session.contextProjection
                    || copy.session.keys != alone.session.keys || copy.session.display != alone.session.display {
                    Issue.record("round \(round) [\(scenario.name)]: a copy ended as \(copy.screen.string), alone \(alone.screen.string)")
                    return
                }
            }
            previous = Array(events[split...])
        }
    }

    static let resetPrefixes = ["tooi", "tooi ", "vn", "vn ", "been", "been ", "xin. ", "xin.", "xin\\N", "tieeng", "Toi"]
    static let resetSuffixes = ["s ", "<s ", "vn ", "toi ", "\\Ntoi ", "j", "<n "]

    /// Spec §5/§8: a reset ends ownership. Host text before the session stays as it was, nothing typed before the
    /// reset is edited afterwards, and the reset is no sentence start.
    @Test(arguments: SessionScenario.all)
    func resetCannotRewriteInitialText(_ base: SessionScenario) {
        for options in Options.all {
            let scenario = base.with(options)
            for prefix in Self.resetPrefixes {
                for suffix in Self.resetSuffixes {
                    var checker = SessionChecker(scenario)
                    checker.type(prefix)
                    let field = checker.screen
                    checker.feed(.reset)
                    #expect(checker.screen == field)
                    checker.type(suffix)
                    #expect(checker.failure == nil, "\(checker.failure ?? "")")
                    #expect(checker.screen.string.hasPrefix(scenario.initialText), "\(prefix)|\(suffix)")
                    // After a reset the session knows nothing before the caret: a fresh session without context
                    // typing the rest over the same field ends the same.
                    var fresh = TypingSession(options: options, settings: scenario.settings, rules: scenario.rules)
                    var expected = field
                    for event in Script.events(suffix) { expected.apply(event, fresh.handle(event)) }
                    #expect(checker.screen == expected, "\(prefix)|\(suffix): \(checker.screen.string) != \(expected.string)")
                }
            }
        }
        // Rows derived by hand (Telex).
        let rows: [(SessionScenario, String, String)] = [
            (.baseline, "tooi|s ", Self.host + "tôis "),
            (.unknownCasing, "xin. |toi", Self.host + "xin. toi"),
            (.documentStartCasing, "xin. |toi", "Xin. toi"),
            (.midSentenceCasing, "xin. |toi", Self.host + "xin. toi"),
            (.macros, "v|n ", Self.host + "vn "),
            (.macros, "vn|<n ", Self.host + "vn "),
            (.exclusions, "bee|n ", Self.host + "bên "),
            (.exclusions, "been|<n ", Self.host + "bên "),
            (.collision, "been|<n ", Self.host + "bên "),
        ]
        for (scenario, script, field) in rows where scenario.name == base.name {
            var checker = SessionChecker(scenario)
            checker.type(script)
            #expect(checker.failure == nil, "\(checker.failure ?? "")")
            expectSameScalars(checker.screen.string, field, script)
        }
    }

    /// Spec §5/§6: Escape, navigation, reset and Tab never expand a macro, also when typing goes on after them.
    @Test(arguments: Options.all)
    func abandonNeverExpands(_ options: Options) {
        for base in [SessionScenario.macros, .collision, .exclusions] {
            let scenario = base.with(options)
            for word in scenario.words {
                for abandon in [Event.endWord, .reset, .char("\t")] {
                    for rest in ["", " ", ".", "\\N", "<" + String(word.last!) + " ", "<<" + String(word.last!) + " "] {
                        var checker = SessionChecker(scenario)
                        checker.type(word)
                        checker.feed(abandon)
                        checker.type(rest)
                        #expect(checker.failure == nil, "\(checker.failure ?? "")")
                        for macro in scenario.macros {
                            #expect(
                                !checker.screen.string.contains(macro.replacement),
                                "\(word) \(Checker.describe(abandon)) \(rest): \(checker.screen.string)"
                            )
                        }
                    }
                }
            }
        }
    }

    static let b30 = String(repeating: "b", count: 30)

    /// Bounded word, token, frame and casing, and the spec's scripts in each declared context. Every field is derived
    /// by hand from the spec, not from a session.
    static let transitions: [SessionTransition] = {
        let h = SessionScenario.hostPrefix
        let vni = Options(inputMethod: .vni)
        let off = Options(spelling: .off)
        func spaces(_ count: Int) -> String { String(repeating: " ", count: count) }
        func deletes(_ count: Int) -> String { String(repeating: "<", count: count) }
        let b30 = Self.b30
        let b31 = String(repeating: "b", count: 31)
        var rows: [SessionTransition] = []
        for scenario in [SessionScenario.baseline, .unknownCasing, .midSentenceCasing, .exclusions, .macros] {
            // Spec §10 scripts with the host prefix unknown or mid-sentence: nothing is capitalized.
            rows += [
                SessionTransition(scenario, "[[", h + "["),
                SessionTransition(scenario, "xin [[a", h + "xin [a"),
                SessionTransition(scenario, "toi la <<<b", h + "toi b"),
                SessionTransition(scenario, "chao ban.< toi", h + "chao ban toi"),
                // With spelling off, key 32 still composes and key 33 turns the word literal.
                SessionTransition(scenario, off, b30 + "as", h + b30 + "á"),
                SessionTransition(scenario, off, b31 + "as", h + b31 + "as"),
                // Within 256 units deleting the breaks reopens the word; past them it is no longer owned.
                SessionTransition(scenario, "toi" + spaces(200) + deletes(200) + "s", h + "tói"),
                SessionTransition(scenario, "toi" + spaces(300) + deletes(300) + "s", h + "tois"),
            ]
        }
        rows += [
            SessionTransition(.baseline, "tooi ", h + "tôi "),
            SessionTransition(.baseline, "xin. toi", h + "xin. toi"),

            SessionTransition(.unknownCasing, "tooi ", h + "tôi "),
            SessionTransition(.unknownCasing, "xin. toi", h + "xin. Toi"),
            SessionTransition(.unknownCasing, "xin\\Ntoi", h + "xin\nToi"),
            SessionTransition(.unknownCasing, "xin.\\Ttoi", h + "xin.\ttoi"),
            SessionTransition(.unknownCasing, "xin. |toi", h + "xin. toi"),
            SessionTransition(.unknownCasing, "xin. << toi", h + "xin toi"),
            SessionTransition(.unknownCasing, "xin. toi <s", h + "xin. Tói"),
            SessionTransition(.unknownCasing, "xin. toi <<<<ban", h + "xin. Ban"),
            // The sentence end is known while it fits the 256-unit context.
            SessionTransition(.unknownCasing, "xin." + spaces(255) + "toi", h + "xin." + spaces(255) + "Toi"),
            SessionTransition(.unknownCasing, "xin." + spaces(256) + "toi", h + "xin." + spaces(256) + "toi"),

            SessionTransition(.documentStartCasing, "tooi ", "Tôi "),
            SessionTransition(.documentStartCasing, "[[", "["),
            SessionTransition(.documentStartCasing, "xin [[a", "Xin [a"),
            SessionTransition(.documentStartCasing, "toi la <<<b", "Toi b"),
            SessionTransition(.documentStartCasing, "chao ban.< toi", "Chao ban toi"),
            SessionTransition(.documentStartCasing, "text ", "Text "),
            SessionTransition(.documentStartCasing, "xin. |toi", "Xin. toi"),
            SessionTransition(.documentStartCasing, "toi <<<<ban", "Ban"),
            SessionTransition(.documentStartCasing, "Bb" + b30 + "as", "Bb" + b30 + "as"),
            SessionTransition(.documentStartCasing, b30 + "bbas", "B" + b31 + "as"),
            // The document start is known while the typed text fits the context.
            SessionTransition(.documentStartCasing, spaces(256) + "toi", spaces(256) + "Toi"),
            SessionTransition(.documentStartCasing, spaces(257) + "toi", spaces(257) + "toi"),

            SessionTransition(.midSentenceCasing, "tooi ", h + "tôi "),
            SessionTransition(.midSentenceCasing, "xin. toi", h + "xin. Toi"),
            SessionTransition(.midSentenceCasing, "\\Ntoi", h + "\nToi"),
            SessionTransition(.midSentenceCasing, "<<. toi", "host prefix. Toi"),
            SessionTransition(.midSentenceCasing, "xin. |toi", h + "xin. toi"),

            SessionTransition(.exclusions, "been ", h + "been "),
            SessionTransition(.exclusions, "test ", h + "test "),
            SessionTransition(.exclusions, "boss ", h + "boss "),
            SessionTransition(.exclusions, "too ", h + "too "),
            SessionTransition(.exclusions, "TOO ", h + "TOO "),
            SessionTransition(.exclusions, "Been ", h + "Been "),
            // Only the whole word is excluded.
            SessionTransition(.exclusions, "tooi ", h + "tôi "),
            SessionTransition(.exclusions, "toon ", h + "tôn "),
            SessionTransition(.exclusions, "been\\E", h + "bên"),
            SessionTransition(.exclusions, "been\\N", h + "been\n"),
            SessionTransition(.exclusions, "been\\T", h + "been\t"),
            SessionTransition(.exclusions, "been.", h + "been."),
            SessionTransition(.exclusions, "been <", h + "been"),
            SessionTransition(.exclusions, "been <<", h + "bê"),
            SessionTransition(.exclusions, "been <<n ", h + "been "),

            SessionTransition(.macros, "vn ", h + "Việt Nam "),
            SessionTransition(.macros, "VN ", h + "Việt Nam "),
            SessionTransition(.macros, vni, "vn ", h + "Việt Nam "),
            // The token is the composed text: four keys, three characters.
            SessionTransition(.macros, "tooi ", h + "nội dung "),
            SessionTransition(.macros, "TOOI ", h + "nội dung "),
            SessionTransition(.macros, vni, "to6i ", h + "nội dung "),
            SessionTransition(.macros, "vn\\N", h + "Việt Nam\n"),
            SessionTransition(.macros, "vn.", h + "Việt Nam."),
            SessionTransition(.macros, "vn\\T", h + "vn\t"),
            SessionTransition(.macros, "vn\\E ", h + "vn "),
            SessionTransition(.macros, "vn\\E<n ", h + "vn "),
            SessionTransition(.macros, ".vn ", h + ".vn "),
            SessionTransition(.macros, "xvn ", h + "xvn "),
            SessionTransition(.macros, "vn vn ", h + "Việt Nam Việt Nam "),
            // No expansion again inside an expanded token; the replacement is literal text.
            SessionTransition(.macros, "tooi.vn ", h + "nội dung.vn "),
            SessionTransition(.macros, "vn <", h + "Việt Nam"),
            SessionTransition(.macros, "vn << ", h + "Việt Na "),
            SessionTransition(.macros, "vn <s ", h + "Việt Nams "),
            SessionTransition(.macros, "tooi <<", h + "nội dun"),

            // Telex shows `bên`, so only the exclusion could match; VNI shows `been`, so both do and the exclusion wins.
            SessionTransition(.collision, "been ", h + "been "),
            SessionTransition(.collision, "Been ", h + "Been "),
            SessionTransition(.collision, "been\\N", h + "been\n"),
            SessionTransition(.collision, "been\\E", h + "bên"),
            SessionTransition(.collision, "bee ", h + "bê "),
            SessionTransition(.collision, "been <<n ", h + "been "),
            SessionTransition(.collision, vni, "been ", h + "been "),
            SessionTransition(.collision, vni, "Been.", h + "Been."),
            SessionTransition(.collision, vni, "BEEN\\N", h + "BEEN\n"),
            SessionTransition(.collision, vni, "beens ", h + "beens "),
        ]
        return rows
    }()

    @Test(arguments: SessionInvariantTests.transitions)
    func fixedTransitions(_ row: SessionTransition) {
        var checker = SessionChecker(row.scenario)
        checker.type(row.script)
        #expect(checker.failure == nil, "\(checker.failure ?? "")")
        expectSameScalars(checker.screen.string, row.field, row.script)
    }
}
