import Testing
import DauKeyEngine
import DauKeyHook

@Suite struct ContextEvidenceTests {
    /// Two reads of one request that disagree, or a prior observation newer than the read, are unconfirmed; the gate
    /// ignores them and the prior observation stays.
    @Test func inconsistentReadsAreUnconfirmed() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        let prior = rig.prior
        rig.type("t")
        #expect(rig.read(before: rig.host("", at: 0), after: rig.host("t", at: 1)) == Verdict(.unconfirmed, .ignored))
        #expect(rig.prior == prior)

        let read = rig.host("t", at: 1)
        let ticket = read.ticket
        let newer = ContextTicket(
            generation: ticket.generation, watermark: ticket.watermark + 1, processID: ticket.processID
        )
        let otherField = ContextTarget(processID: contextProcess, elementID: 2)
        for after in [
            rig.host("t", at: 1, ticket: newer), rig.host("t", at: 1, target: otherField),
            rig.host("t", at: 1, selecting: 1), rig.host("t", at: 1, fromDocumentStart: false),
        ] {
            #expect(ContextEvidence.evaluate(
                priorActual: nil, before: read, after: after, expected: nil
            ) == .unconfirmed)
        }
        #expect(ContextEvidence.evaluate(
            priorActual: rig.host("t", at: 1, ticket: newer), before: read, after: read, expected: nil
        ) == .unconfirmed)
    }

    /// With no prior observation a consistent read is settled, with or without an expectation.
    @Test func firstReadIsSettled() {
        var rig = ContextRig()
        let state = rig.host("hello", at: 5)
        #expect(ContextEvidence.evaluate(priorActual: nil, before: state, after: state, expected: nil) == .settled)
        rig.read(rig.host("", at: 0))
        rig.type("hello")
        let expected = rig.request.expected
        #expect(expected != nil)
        #expect(ContextEvidence.evaluate(
            priorActual: nil, before: rig.host("hello", at: 5), after: rig.host("hello", at: 5), expected: expected
        ) == .settled)
    }

    /// A ticket changing alone is freshness, not a host transition: prior T1 (10,0,"hello "), then T2 reads the same
    /// state after a click invalidation; settled, and with no expectation while awaiting the host, ignored.
    @Test func ticketChangeAloneIsNotHostTransition() {
        var rig = ContextRig()
        let first = rig.request.ticket
        #expect(rig.read(rig.host("hello ", at: 10, fromDocumentStart: false))
            == Verdict(.settled, accepted("hello ", fromDocumentStart: false)))
        rig.click()
        #expect(rig.request.ticket != first)
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("hello ", at: 10, fromDocumentStart: false)) == Verdict(.settled, .ignored))
    }

    /// A stable intermediate range is a confirmed transition; the gate ignores it while output is pending and finds a
    /// mismatch once nothing is pending.
    @Test func stableIntermediateRangeIsTransitionConfirmed() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        #expect(rig.read(rig.host("to", at: 2)) == Verdict(.transitionConfirmed, .ignored))
        #expect(rig.read(rig.host("toi", at: 3)) == Verdict(.transitionConfirmed, accepted("toi")))
        #expect(rig.read(rig.host("to", at: 2)) == Verdict(.transitionConfirmed, .mismatch))
    }

    /// While a tone key is pending, the host still showing the text before that key at the expected range is ignored.
    @Test func preKeySuffixMismatchIgnoredWhilePending() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        rig.read(rig.host("toi", at: 3))
        rig.type("s")
        #expect(rig.request.expected?.selection == ContextSelection(location: 3, length: 0))
        #expect(rig.request.expected?.context.prefix == "tói")
        #expect(rig.read(rig.host("toi", at: 3)) == Verdict(.settled, .ignored))
        #expect(rig.read(rig.host("tói", at: 3)) == Verdict(.transitionConfirmed, accepted("tói")))
    }

    /// A sample matching the expectation is accepted even when it equals the prior observation: the reader published
    /// the applied state, a key-up made it stale, and the next request reads the same state.
    @Test func matchingSampleAcceptedEvenWhenSettled() throws {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        let applied = rig.host("toi", at: 3)
        let early = try #require(ContextEvidence.publish(
            before: applied, after: applied, expected: rig.request.expected, isLatest: true, priorActual: &rig.prior
        ))
        rig.keyUp()
        #expect(rig.deliver(early) == .ignored)
        #expect(rig.read(rig.host("toi", at: 3)) == Verdict(.settled, accepted("toi")))
    }

    /// With no expectation, text changing alone at the same element and range stays settled; while output is pending
    /// the gate ignores it.
    @Test func textOnlyChangeWithoutExpectationIsSettled() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        rig.read(rig.host("toi", at: 3))
        rig.unavailable()
        rig.type("s")
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("tói", at: 3)) == Verdict(.settled, .ignored))
    }

    /// Prior (2,"ti"), expected (3,"tiê"), the host showing (3,"tie"): a confirmed transition the gate ignores; the
    /// caught-up host is accepted. Two tone and mark outputs behind are ignored too; with no expectation after
    /// unavailable, a lagging transition whose text the session does not own is ignored rather than accepted.
    @Test func laggedSameCaretTextCannotResetWord() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("ti")
        #expect(rig.read(rig.host("ti", at: 2)).acceptance == accepted("ti"))
        rig.type("ee")
        #expect(rig.request.expected == ContextExpectation(
            target: contextField, selection: ContextSelection(location: 3, length: 0),
            context: TextContext(prefix: "tiê", startsAtDocumentStart: true)
        ))
        #expect(rig.read(rig.host("tie", at: 3)) == Verdict(.transitionConfirmed, .ignored))
        #expect(rig.read(rig.host("tiê", at: 3)) == Verdict(.transitionConfirmed, accepted("tiê")))

        // Two outputs behind: `e` and `s` both change the word in place.
        var twoBehind = ContextRig()
        twoBehind.read(twoBehind.host("", at: 0))
        twoBehind.type("tie")
        #expect(twoBehind.read(twoBehind.host("tie", at: 3)).acceptance == accepted("tie"))
        twoBehind.type("es")
        #expect(twoBehind.request.expected?.context.prefix == "tiế")
        #expect(twoBehind.read(twoBehind.host("tie", at: 3)) == Verdict(.settled, .ignored))
        #expect(twoBehind.read(twoBehind.host("tiê", at: 3)) == Verdict(.transitionConfirmed, .ignored))
        #expect(twoBehind.read(twoBehind.host("tiế", at: 3)) == Verdict(.transitionConfirmed, accepted("tiế")))

        // The same lag with no expectation after unavailable.
        var lost = ContextRig()
        lost.read(lost.host("", at: 0))
        lost.type("ti")
        #expect(lost.read(lost.host("ti", at: 2)).acceptance == accepted("ti"))
        lost.unavailable()
        lost.type("ees")
        #expect(lost.request.expected == nil)
        let lagging = lost.host("tie", at: 3)
        #expect(!lost.session.canSynchronizeContext(lagging.context))
        #expect(lost.read(lagging) == Verdict(.transitionConfirmed, .ignored))
        #expect(lost.read(lost.host("tiê", at: 3)) == Verdict(.settled, .ignored))
        #expect(lost.read(lost.host("tiế", at: 3)) == Verdict(.settled, .ignored))
        lost.type("n")
        #expect(lost.read(lost.host("tiến", at: 4)) == Verdict(.transitionConfirmed, accepted("tiến")))
    }

    /// After `toi` is accepted with nothing pending, a same-length autocorrect to `tai` is a mismatch; while output is
    /// pending the same shape is ignored.
    @Test func sameLengthAutocorrectOutsidePendingDropsOwnership() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        #expect(rig.read(rig.host("toi", at: 3)).acceptance == accepted("toi"))
        #expect(rig.read(rig.host("tai", at: 3)) == Verdict(.transitionConfirmed, .mismatch))

        var pending = ContextRig()
        pending.read(pending.host("", at: 0))
        pending.type("toi")
        #expect(pending.read(pending.host("tai", at: 3)) == Verdict(.transitionConfirmed, .ignored))
    }

    /// A read superseded by a newer request is neither published nor kept as the prior observation, so the newer
    /// read still sees the click's transition.
    @Test func supersededReadCannotConsumeTransition() throws {
        var rig = ContextRig()
        rig.read(rig.host("hello ", at: 10, fromDocumentStart: false))
        let prior = rig.prior
        rig.click()
        let superseded = rig.request
        let relocated = rig.host("hell", at: 4)
        rig.keyUp()
        #expect(ContextEvidence.publish(
            before: relocated, after: relocated, expected: superseded.expected, isLatest: false,
            priorActual: &rig.prior
        ) == nil)
        #expect(rig.prior == prior)

        let current = rig.host("hell", at: 4)
        #expect(ContextEvidence.evaluate(
            priorActual: relocated, before: current, after: current, expected: rig.request.expected
        ) == .settled)
        #expect(rig.read(current) == Verdict(.transitionConfirmed, accepted("hell")))
    }

    /// The inline-suggestion hint ignores only the selected length, where the location and known text match the
    /// expectation: a wrong location is ignored while output is pending and a mismatch otherwise, and a selection
    /// without the hint gets no exception. A notification re-reading a request issued while output was pending is
    /// judged by the gate's state after the acceptance.
    @Test func inlineSuggestionRangeKeepsLocationAndOwnership() {
        var rig = ContextRig()
        rig.read(rig.host("ab ", at: 5, fromDocumentStart: false))
        rig.type("ta")
        #expect(rig.read(rig.host("ab ta", at: 7, selecting: 4, fromDocumentStart: false), inline: true)
            == Verdict(.transitionConfirmed, accepted("ab ta", fromDocumentStart: false)))
        #expect(rig.gate.hasSelection)
        #expect(rig.projection.hasOwnedSuffix)

        rig.type("n")
        #expect(!rig.gate.hasSelection)
        #expect(rig.request.expected?.selection == ContextSelection(location: 8, length: 0))
        #expect(rig.read(rig.host("ab tan", at: 8, selecting: 3, fromDocumentStart: false), inline: true).acceptance
            == accepted("ab tan", fromDocumentStart: false))

        rig.type("g")
        let shifted = rig.host("ab tang", at: 11, selecting: 2, fromDocumentStart: false)
        let selected = rig.host("ab tang", at: 9, selecting: 3, fromDocumentStart: false)
        #expect(rig.read(shifted, inline: true).acceptance == .ignored)
        #expect(rig.read(selected).acceptance == .ignored)
        #expect(rig.read(rig.host("ab tang", at: 9, selecting: 2, fromDocumentStart: false), inline: true).acceptance
            == accepted("ab tang", fromDocumentStart: false))
        #expect(rig.read(rig.host("ab tang", at: 9, fromDocumentStart: false), inline: true).acceptance
            == accepted("ab tang", fromDocumentStart: false))

        // The same request, issued while `g` was pending, read again after the acceptance.
        #expect(rig.read(shifted, inline: true) == Verdict(.transitionConfirmed, .mismatch))
        #expect(rig.read(selected) == Verdict(.transitionConfirmed, .mismatch))
    }
}
