import Testing
@testable import DauKeyEngine

@Suite struct SessionCasingTests {
    static let autoCapitalize = SessionSettings(autoCapitalize: true)
    static let documentStart = TextContext(prefix: "", startsAtDocumentStart: true)

    @Test(arguments: [
        ("[[", "["), ("xin [[a", "Xin [a"), ("toi la <<<b", "Toi b"), ("chao ban.< toi", "Chao ban toi"),
        // Spelling restore keeps the word's casing; the raw keys stay `text`.
        ("text ", "Text "),
        // The decision is fixed when the word starts, so a reopened word keeps it, also after a restore turns back
        // into composing (baseline `text <<<s` -> `té`).
        ("toi <s", "Tói"), ("text <<<s", "Té"),
        // Deleting a sentence end or a newline before the next whitespace removes the sentence start.
        ("xin. << toi", "Xin toi"), ("xin\\N< toi", "Xin toi"),
        // A newline starts a sentence; a Tab is not assumed to.
        ("xin\\Ntoi", "Xin\nToi"), ("xin.\\Ttoi", "Xin.\ttoi"), ("xin. \\Ttoi", "Xin. \ttoi"),
    ])
    func documentStartRows(_ row: (String, String)) {
        var probe = SessionProbe(settings: Self.autoCapitalize, context: Self.documentStart)
        probe.script(row.0)
        expectSameScalars(probe.text, row.1, row.0)
    }

    @Test(arguments: [
        ("toi", "toi"), (". toi", ". Toi"), ("! toi", "! Toi"), ("? toi", "? Toi"), (".toi", ".toi"),
        // An opening quote or bracket does not use up the sentence start.
        (". \"toi", ". \"Toi"), ("xin. (toi", "xin. (Toi"),
        // A newline typed by the user starts a sentence again.
        ("xin\\Ntoi", "xin\nToi"),
        // Deleting the sentence end removes the evidence.
        ("xin. << toi", "xin toi"), ("? << toi", " toi"),
        // A reset is not a sentence start.
        ("xin. |toi", "xin. toi"),
    ])
    func unknownContextRows(_ row: (String, String)) {
        var probe = SessionProbe(settings: Self.autoCapitalize)
        probe.script(row.0)
        expectSameScalars(probe.text, row.1, row.0)
    }

    @Test func removingSentenceWhitespaceDisarmsCasing() {
        var probe = SessionProbe(settings: Self.autoCapitalize)
        probe.script(". <toi")
        #expect(probe.text == ".toi")
    }

    @Test func knownMidSentenceIsNotCapitalized() {
        var probe = SessionProbe(
            initialText: "chao ", settings: Self.autoCapitalize,
            context: TextContext(prefix: "chao ", startsAtDocumentStart: true)
        )
        probe.script("ban")
        #expect(probe.text == "chao ban")
    }

    @Test func resetMidSentenceIsNotCapitalized() {
        var probe = SessionProbe(settings: Self.autoCapitalize, context: Self.documentStart)
        probe.script("xin |chao")
        #expect(probe.text == "Xin chao")
    }

    @Test func autoCapitalizeOffKeepsTypedCase() {
        var probe = SessionProbe(context: Self.documentStart)
        probe.script("xin. Chao\\Nban")
        #expect(probe.text == "xin. Chao\nban")
    }

    @Test func settingChangeAppliesToNextWord() {
        var on = SessionProbe(context: Self.documentStart)
        on.type("toi")
        on.session.setSettings(Self.autoCapitalize)
        on.type("s. ban")
        expectSameScalars(on.text, "tói. Ban")

        var off = SessionProbe(settings: Self.autoCapitalize, context: Self.documentStart)
        off.type("to")
        off.session.setSettings(SessionSettings())
        off.type("i. ban")
        #expect(off.text == "Toi. ban")
    }

    @Test func lateContextDoesNotRecaseCurrentWord() {
        var probe = SessionProbe(settings: Self.autoCapitalize)
        probe.type("toi")
        probe.synchronize(TextContext(prefix: "toi", startsAtDocumentStart: true))
        #expect(probe.session.contextProjection.caretDeltaUTF16 == 0)
        probe.type("s ban")
        expectSameScalars(probe.text, "tói ban")
    }

    @Test func matchingContextPreservesReopenFrame() {
        var probe = SessionProbe(settings: Self.autoCapitalize)
        probe.type("toi.")
        #expect(probe.session.contextProjection.hasOwnedSuffix)
        probe.synchronize(TextContext(prefix: "toi.", startsAtDocumentStart: true))
        probe.script("<s")
        expectSameScalars(probe.text, "tói")
    }

    @Test func mismatchingContextDoesNotMutateSession() {
        var probe = SessionProbe(settings: Self.autoCapitalize, context: Self.documentStart)
        probe.type("xin. toi")
        let copy = probe
        for prefix in ["Xin. Tao", "xin. toi", "Xin. To"] {
            let context = TextContext(prefix: prefix, startsAtDocumentStart: true)
            #expect(!probe.session.canSynchronizeContext(context))
            probe.synchronize(context, accepted: false)
        }
        #expect(probe.session.contextProjection == copy.session.contextProjection)
        var original = copy
        probe.script("<s. ban")
        original.script("<s. ban")
        expectSameScalars(probe.text, "Xin. Tó. Ban")
        #expect(probe.text == original.text)
        #expect(probe.session.contextProjection == original.session.contextProjection)
    }

    @Test func ownedSuffixMatchKeepsWordAndReplacesUnownedContext() {
        var probe = SessionProbe(initialText: "abc", settings: Self.autoCapitalize)
        probe.type(". ")
        #expect(!probe.session.contextProjection.hasOwnedSuffix)
        probe.synchronize(TextContext(prefix: "abc. ", startsAtDocumentStart: false))
        #expect(probe.session.contextProjection.context == TextContext(prefix: "abc. ", startsAtDocumentStart: false))
        probe.type("toi")
        #expect(probe.session.contextProjection.hasOwnedSuffix)
        #expect(probe.session.canSynchronizeContext(TextContext(prefix: "x Toi", startsAtDocumentStart: false)))
        #expect(!probe.session.canSynchronizeContext(TextContext(prefix: "x toi", startsAtDocumentStart: false)))
        #expect(probe.text == "abc. Toi")
    }

    @Test func invalidatedContextKeepsLocalEvidenceOnly() {
        // Knowledge read from the host is dropped, also for a word reopened later.
        var known = SessionProbe(settings: Self.autoCapitalize, context: Self.documentStart)
        known.type("toi ")
        known.session.invalidateContext()
        #expect(known.session.contextProjection.caretDeltaUTF16 == nil)
        #expect(!known.session.contextProjection.context.startsAtDocumentStart)
        known.script("<s")
        expectSameScalars(known.text, "Tói")
        known.script("<<<ban")
        #expect(known.text == "ban")

        var control = SessionProbe(settings: Self.autoCapitalize, context: Self.documentStart)
        control.script("toi <<<<ban")
        #expect(control.text == "Ban")

        // Breaks the session tracked itself still count.
        var local = SessionProbe(settings: Self.autoCapitalize)
        local.script("xin. ")
        local.session.invalidateContext()
        local.script("toi\\N")
        local.session.invalidateContext()
        local.script("ban")
        #expect(local.text == "xin. Toi\nBan")
    }

    @Test func contextTruncationKeepsGraphemes() {
        let b254 = String(repeating: "b", count: 254)
        for split in ["👍🏽", "e\u{302}\u{301}"] {
            let context = TextContext(prefix: "x" + split + b254, startsAtDocumentStart: true)
            #expect(context.prefix == b254, "\(split)")
            #expect(!context.startsAtDocumentStart)
        }
        let fits = String(repeating: "b", count: 252) + "👍🏽"
        let whole = TextContext(prefix: fits, startsAtDocumentStart: true)
        #expect(whole.prefix == fits && whole.startsAtDocumentStart)
        let trimmed = TextContext(prefix: "y" + fits, startsAtDocumentStart: true)
        #expect(trimmed.prefix == fits && !trimmed.startsAtDocumentStart)

        // A trimmed prefix is no evidence of the document start.
        for (spaces, expected) in [(255, "Toi"), (256, "Toi"), (257, "toi"), (300, "toi")] {
            let blank = String(repeating: " ", count: spaces)
            var probe = SessionProbe(
                initialText: blank, settings: Self.autoCapitalize,
                context: TextContext(prefix: blank, startsAtDocumentStart: true)
            )
            probe.type("toi")
            #expect(probe.text == blank + expected, "\(spaces) spaces")
        }

        // The caret delta counts the text actually inserted and deleted, while the projected prefix stays bounded.
        let long = "x👍🏽" + b254
        var probe = SessionProbe(
            initialText: long, settings: Self.autoCapitalize,
            context: TextContext(prefix: long, startsAtDocumentStart: true)
        )
        #expect(probe.session.contextProjection.context == TextContext(prefix: b254, startsAtDocumentStart: false))
        #expect(probe.session.contextProjection.caretDeltaUTF16 == 0)
        probe.type(" 👍🏽as")
        #expect(probe.session.contextProjection.caretDeltaUTF16 == 6)
        #expect(probe.session.contextProjection.context.prefix.utf16.count == 256)
        #expect(probe.session.contextProjection.context.prefix.hasSuffix(" 👍🏽á"))
        probe.script("<<")
        #expect(probe.session.contextProjection.caretDeltaUTF16 == 1)
        probe.script("<<")
        #expect(probe.session.contextProjection.caretDeltaUTF16 == -1)
        #expect(probe.text == "x👍🏽" + String(repeating: "b", count: 253))
    }

    @Test func backspaceBeyondTrackedBreaksDoesNotDeleteHostPrefix() {
        let context = TextContext(prefix: "xin ", startsAtDocumentStart: true)
        // Within the tracked breaks the word is reopened.
        var near = SessionProbe(initialText: "xin ", settings: Self.autoCapitalize, context: context)
        near.type("toi" + String(repeating: " ", count: 200))
        near.script(String(repeating: "<", count: 200) + "s")
        expectSameScalars(near.text, "xin tói")

        // Past the bound the word is no longer owned: deleting the breaks does not reopen or edit it.
        var far = SessionProbe(initialText: "xin ", settings: Self.autoCapitalize, context: context)
        far.type("toi" + String(repeating: " ", count: 300))
        #expect(!far.session.contextProjection.hasOwnedSuffix)
        far.script(String(repeating: "<", count: 300))
        #expect(far.session.contextProjection.caretDeltaUTF16 == nil)
        far.script("s")
        #expect(far.text == "xin tois")
        far.script("<<<<<<<<a")
        #expect(far.text == "a")
    }
}
