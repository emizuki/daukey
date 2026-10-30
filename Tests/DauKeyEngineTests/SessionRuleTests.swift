import Testing
@testable import DauKeyEngine

@Suite struct SessionRuleTests {
    static let vn = MacroRule(trigger: "vn", replacement: "Việt Nam")
    static let exclusions = RuleTables(exclusions: ["been", "test", "boss", "too"])
    static let documentStart = TextContext(prefix: "", startsAtDocumentStart: true)

    static func typed(_ script: String, rules: RuleTables, settings: SessionSettings = SessionSettings()) -> String {
        var probe = SessionProbe(settings: settings, rules: rules)
        probe.script(script)
        return probe.text
    }

    // MARK: Exclusions

    @Test(arguments: [
        ("been ", "been "), ("test ", "test "), ("boss ", "boss "),
        // Only the whole word is excluded: `too` does not block `tooi`.
        ("tooi ", "tôi "),
        // Return and Tab restore the raw word before the key itself goes through.
        ("been\\N", "been\n"), ("been\\T", "been\t"),
        // Ending the word without a textual boundary keeps what was composed.
        ("been\\E", "bên"),
        // The raw word keeps the case the user typed.
        ("Been ", "Been "),
        // Composition is still visible while the word is typed.
        ("been", "bên"),
    ])
    func exclusionsCorrectRenderedTextOnlyAtTypedBoundary(_ row: (String, String)) {
        expectSameScalars(Self.typed(row.0, rules: Self.exclusions), row.1, row.0)
    }

    @Test func exclusionWinsOverMacroAndKeepsRawCase() {
        var probe = SessionProbe(
            settings: SessionSettings(autoCapitalize: true),
            rules: RuleTables(macros: [MacroRule(trigger: "been", replacement: "X")], exclusions: ["been"]),
            context: Self.documentStart
        )
        probe.script("been ")
        #expect(probe.text == "been ")
    }

    // MARK: Macros

    @Test(arguments: [
        ("vn ", "Việt Nam "), ("vn\\N", "Việt Nam\n"), ("vn.", "Việt Nam."),
        // The token `a.vn` is tracked as a whole, so `vn` does not match its end.
        ("a.vn ", "a.vn "),
        // The expansion happens at the `.`; the rest of the token is never matched.
        ("vn.com", "Việt Nam.com"), ("vn.com ", "Việt Nam.com "),
        // Escape, navigation, and Tab never expand.
        ("vn\\E ", "vn "), ("vn\\T", "vn\t"),
        // Unicode punctuation is tried; digits and emoji are not, and stay in the token.
        ("vn!", "Việt Nam!"), ("vn?", "Việt Nam?"), ("vn,", "Việt Nam,"), ("vn…", "Việt Nam…"),
        ("vn1 ", "vn1 "), ("vn👍 ", "vn👍 "),
        // A bracket that breaks the word is punctuation; one that composes a letter is not a delimiter.
        ("vn[", "Việt Nam["), ("tr[ ", "trơ "),
    ])
    func macroFinishReasons(_ row: (String, String)) {
        let rules = RuleTables(macros: [Self.vn, MacroRule(trigger: "tr", replacement: "trong")])
        expectSameScalars(Self.typed(row.0, rules: rules), row.1, row.0)
    }

    @Test func punctuationStaysInTheToken() {
        let rules = RuleTables(macros: [
            MacroRule(trigger: ":)", replacement: "☺"), MacroRule(trigger: "v.v.", replacement: "vân vân"),
        ])
        expectSameScalars(Self.typed(":) ", rules: rules), "☺ ")
        expectSameScalars(Self.typed("v.v. ", rules: rules), "vân vân ")
        expectSameScalars(Self.typed("v.v.<. ", rules: rules), "vân vân ")
    }

    @Test func bypassSkipsTheMacroOfOneEventOnly() {
        let rules = RuleTables(macros: [Self.vn])
        var space = SessionProbe(rules: rules)
        space.type("vn")
        space.send(.char(" "), bypassMacro: true)
        space.type("vn ")
        expectSameScalars(space.text, "vn Việt Nam ")

        var newline = SessionProbe(rules: rules)
        newline.type("vn")
        newline.send(.char("\n"), bypassMacro: true)
        newline.type("vn\n")
        expectSameScalars(newline.text, "vn\nViệt Nam\n")
    }

    @Test func macroMatchesTheComposedText() {
        let composed = RuleTables(macros: [MacroRule(trigger: "tôi", replacement: "mình")])
        expectSameScalars(Self.typed("tooi ", rules: composed), "mình ")
        let raw = RuleTables(macros: [MacroRule(trigger: "tooi", replacement: "mình")])
        expectSameScalars(Self.typed("tooi ", rules: raw), "tôi ")
    }

    @Test func replacementIsInsertedVerbatim() {
        let signature = RuleTables(macros: [MacroRule(trigger: "ck", replacement: "cảm ơn,\nQuỳnh  ")])
        var probe = SessionProbe(
            settings: SessionSettings(autoCapitalize: true), rules: signature, context: Self.documentStart
        )
        probe.script("ck ")
        expectSameScalars(probe.text, "cảm ơn,\nQuỳnh   ")

        let chained = RuleTables(macros: [
            MacroRule(trigger: "x", replacement: "vn"), Self.vn, MacroRule(trigger: "lap", replacement: "lap lap"),
        ])
        expectSameScalars(Self.typed("x ", rules: chained), "vn ")
        expectSameScalars(Self.typed("lap ", rules: chained), "lap lap ")
    }

    // MARK: Interactions

    @Test func reopenKeepsRuleSnapshot() {
        var probe = SessionProbe(rules: RuleTables(macros: [Self.vn]))
        probe.type("vn")
        probe.send(.char(" "), bypassMacro: true)
        probe.session.setRules(RuleTables(macros: [MacroRule(trigger: "vn", replacement: "VN")]))
        probe.script("< ")
        expectSameScalars(probe.text, "Việt Nam ")
        probe.script("vn ")
        expectSameScalars(probe.text, "Việt Nam VN ")
    }

    static let r1 = RuleTables(macros: [
        MacroRule(trigger: "?!", replacement: "R1"), MacroRule(trigger: "x?!", replacement: "X1"),
    ])
    static let r2 = RuleTables(macros: [
        MacroRule(trigger: "?!", replacement: "R2"), MacroRule(trigger: "x?!", replacement: "X2"),
    ])

    /// A token made only of breaks after whitespace keeps its rules when deleting the whitespace reopens it.
    @Test func reopenedBreakTokenKeepsRuleSnapshot() {
        var probe = SessionProbe(rules: Self.r1)
        probe.type("hi ? ")
        probe.session.setRules(Self.r2)
        probe.script("<! ")
        expectSameScalars(probe.text, "hi R1 ")
    }

    /// A token too long to match is rebuilt from the frame after Backspace shortens it, with the rules it started
    /// with.
    @Test func rebuiltLongTokenKeepsRuleSnapshot() {
        var breakToken = SessionProbe(rules: Self.r1)
        breakToken.type("hi ?..!")
        breakToken.session.setRules(Self.r2)
        breakToken.script("<<<! ")
        expectSameScalars(breakToken.text, "hi R1 ")

        var wordToken = SessionProbe(rules: Self.r1)
        wordToken.type("x?.!")
        wordToken.session.setRules(Self.r2)
        wordToken.script("<<! ")
        expectSameScalars(wordToken.text, "X1 ")
    }

    @Test func editingExcludedWordRecomputesSuppression() {
        expectSameScalars(Self.typed("too <i ", rules: Self.exclusions), "tôi ")
        let suppressed = RuleTables(macros: [MacroRule(trigger: "tôi", replacement: "mình")], exclusions: ["too"])
        expectSameScalars(Self.typed("too <i ", rules: suppressed), "mình ")
        expectSameScalars(Self.typed("been <", rules: Self.exclusions), "been")
        expectSameScalars(Self.typed("been <<", rules: Self.exclusions), "bê")
        expectSameScalars(Self.typed("been < ", rules: Self.exclusions), "been ")
    }

    @Test func knownHostTokenIsNotAnOwnedMacro() {
        let rules = RuleTables(macros: [Self.vn, MacroRule(trigger: "a.vn", replacement: "X")])
        var continued = SessionProbe(
            initialText: "a.", rules: rules, context: TextContext(prefix: "a.", startsAtDocumentStart: true)
        )
        continued.script("vn vn ")
        expectSameScalars(continued.text, "a.vn Việt Nam ")

        var separated = SessionProbe(
            initialText: "a. ", rules: rules, context: TextContext(prefix: "a. ", startsAtDocumentStart: true)
        )
        separated.script("vn ")
        expectSameScalars(separated.text, "a. Việt Nam ")
    }

    @Test func expandedLiteralDoesNotRecomposeOrRecoverTrigger() {
        let rules = RuleTables(macros: [MacroRule(trigger: "x", replacement: "xin")])
        expectSameScalars(Self.typed("x <as", rules: rules), "xinas")
        expectSameScalars(Self.typed("x <as<<<", rules: rules), "xi")
        expectSameScalars(Self.typed("x <", rules: rules), "xin")
        expectSameScalars(Self.typed("x <<", rules: rules), "xi")
        expectSameScalars(Self.typed("x < ", rules: rules), "xin ")
        expectSameScalars(Self.typed("x <as ", rules: rules), "xinas ")
        expectSameScalars(Self.typed("x <<<<<<", rules: rules), "")
    }

    /// A break that joins the character before it ends the token: its characters no longer match the keys typed, and
    /// deleting them edits nothing and never traps.
    @Test func joiningBreakEndsTheToken() {
        var probe = SessionProbe(rules: RuleTables(macros: [MacroRule(trigger: "abc", replacement: "X")]))
        for event: Event in [.char("."), .char("\u{301}"), .char("\u{301}"), .backspace, .backspace] {
            probe.send(event)
        }
        expectSameScalars(probe.text, ".")

        // The token itself stops matching when what it is given joins its last character.
        let joined = MacroToken(rules: RuleTables(macros: [MacroRule(trigger: "abc", replacement: "X")]), eligible: true)
            .appending(".").appending("\u{301}")
        #expect(joined.text == nil && joined.count == 2)
        #expect(joined.droppingLast()?.text == nil)
    }

    @Test func canonicalKeysAndProvisionalLength() {
        let precomposed = "t\u{F4}i"
        let decomposed = "to\u{302}i"
        #expect(RuleTables.key(precomposed) == RuleTables.key(decomposed.uppercased()))
        let lastWins = RuleTables(macros: [
            MacroRule(trigger: precomposed, replacement: "A"), MacroRule(trigger: decomposed, replacement: "B"),
        ])
        expectSameScalars(Self.typed("tooi ", rules: lastWins), "B ")
        let reversed = RuleTables(macros: [
            MacroRule(trigger: decomposed, replacement: "B"), MacroRule(trigger: precomposed, replacement: "A"),
        ])
        expectSameScalars(Self.typed("tooi ", rules: reversed), "A ")

        // Lowercasing only: no full case folding.
        #expect(RuleTables.key("straße") != RuleTables.key("STRASSE"))
        let german = RuleTables(macros: [MacroRule(trigger: "straße", replacement: "X")])
        #expect(german.replacement(for: "STRASSE") == nil)
        #expect(german.replacement(for: "Straße") == "X")

        // A word with more keys than the longest trigger, or a render that Backspace shortens again, still matches.
        let long = RuleTables(macros: [MacroRule(trigger: "người", replacement: "X"), Self.vn])
        expectSameScalars(Self.typed("nguoiwf ", rules: long), "X ")
        expectSameScalars(Self.typed("vnkk<< ", rules: long), "Việt Nam ")

        // A token longer than the longest trigger never matches its end.
        let suffix = RuleTables(macros: [Self.vn, MacroRule(trigger: "x.vn", replacement: "X")])
        expectSameScalars(Self.typed("x.vn ", rules: suffix), "X ")
        expectSameScalars(Self.typed("xx.vn ", rules: suffix), "xx.vn ")
    }

    @Test func tablesRejectIncompleteRows() {
        let tables = RuleTables(
            macros: [
                MacroRule(trigger: "", replacement: "empty"), MacroRule(trigger: "v n", replacement: "space"),
                MacroRule(trigger: "ok", replacement: ""), MacroRule(trigger: "ok", replacement: " kept\n "),
                MacroRule(trigger: "no", replacement: "first"), MacroRule(trigger: "no", replacement: ""),
            ],
            exclusions: ["", "a b", "Been"]
        )
        #expect(tables.replacement(for: "") == nil)
        #expect(tables.replacement(for: "v n") == nil)
        #expect(tables.replacement(for: "OK") == " kept\n ")
        #expect(tables.replacement(for: "no") == "first")
        #expect(!tables.excludes(""))
        #expect(!tables.excludes("a b"))
        #expect(tables.excludes("bEEn"))
    }
}
