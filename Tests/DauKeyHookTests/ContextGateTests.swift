import Testing
import DauKeyEngine
import DauKeyHook

let contextProcess: Int32 = 42
let contextField = ContextTarget(processID: contextProcess, elementID: 1)

/// The producer's evidence for a published read and the gate's verdict on it.
struct Verdict: Equatable {
    let evidence: AnchorEvidence
    let acceptance: ContextAcceptance

    init(_ evidence: AnchorEvidence, _ acceptance: ContextAcceptance) {
        self.evidence = evidence
        self.acceptance = acceptance
    }
}

func accepted(_ prefix: String, fromDocumentStart: Bool = true) -> ContextAcceptance {
    .accepted(TextContext(prefix: prefix, startsAtDocumentStart: fromDocumentStart))
}

/// A real session and gate driven the way the core drives them, with the reader's one prior observation.
struct ContextRig {
    var session = TypingSession()
    var gate = ContextGate()
    var prior: ContextSample?
    /// The latest request the gate issued.
    private(set) var request: ContextRequest

    init() {
        gate.invalidate(processID: contextProcess, awaitingHostChange: false)
        request = gate.request(projection: session.contextProjection)!
    }

    var projection: ContextProjection { session.contextProjection }

    /// Types `text` key by key: input noted, session edited, output submitted, then a request.
    mutating func type(_ text: String) {
        for character in text { press(.char(character)) }
    }

    mutating func press(_ event: Event) {
        gate.noteInput()
        _ = session.handle(event)
        gate.didSubmit()
        issue()
    }

    /// A physical event without text, such as a key-up.
    mutating func keyUp() {
        gate.noteInput()
        issue()
    }

    /// A click the hook saw: the session is reset and the gate awaits the host's relocation.
    mutating func click() {
        _ = session.handle(.reset)
        gate.invalidate(processID: contextProcess, awaitingHostChange: true)
        issue()
    }

    /// The reader could not read the current context.
    mutating func unavailable() {
        gate.markUnavailable()
        session.invalidateContext()
        issue()
    }

    mutating func issue() {
        if let next = gate.request(projection: projection) { request = next }
    }

    /// One raw read of the host, for the latest request unless `ticket` is given; the producer sets its evidence.
    func host(
        _ prefix: String, at location: Int, selecting length: Int = 0, fromDocumentStart: Bool = true,
        target: ContextTarget = contextField, ticket: ContextTicket? = nil
    ) -> ContextSample {
        ContextSample(
            ticket: ticket ?? request.ticket, target: target,
            selection: ContextSelection(location: location, length: length),
            context: TextContext(prefix: prefix, startsAtDocumentStart: fromDocumentStart), evidence: .unconfirmed
        )
    }

    /// The reader reads `state` before and after for the latest request and publishes it; the gate judges it.
    @discardableResult
    mutating func read(_ state: ContextSample, inline: Bool = false) -> Verdict {
        read(before: state, after: state, inline: inline)
    }

    @discardableResult
    mutating func read(before: ContextSample, after: ContextSample, inline: Bool = false) -> Verdict {
        let sample = ContextEvidence.publish(
            before: before, after: after, expected: request.expected, isLatest: true, priorActual: &prior
        )!
        return Verdict(sample.evidence, deliver(sample, inline: inline))
    }

    /// The gate's verdict on a published sample. `inline` is an app with the inline-suggestion workaround; as in the
    /// core, the hint also needs owned text that the sample ends with. An accepted context syncs the session, after a
    /// reset when it selects text that is not such a suggestion.
    mutating func deliver(_ sample: ContextSample, inline: Bool = false) -> ContextAcceptance {
        let owned = session.canSynchronizeContext(sample.context)
        let hint = inline && projection.hasOwnedSuffix && owned
        let acceptance = gate.accept(
            sample, projection: projection, ownedSuffixMatches: owned, allowsInlineSuggestion: hint
        )
        if case .accepted(let context) = acceptance {
            if sample.selection.length > 0, !hint { _ = session.handle(.reset) }
            let synchronized = session.synchronizeContext(context)
            #expect(synchronized)
        }
        return acceptance
    }
}

@Suite struct ContextGateTests {
    /// The expected caret moves by the inserted UTF-16 units from the anchor, not by the trimmed prefix length.
    @Test func checkedUTF16AnchorAfterTrim() throws {
        var rig = ContextRig()
        let text = String(repeating: "abcd ", count: 52)
        #expect(text.utf16.count == 260)
        #expect(rig.read(rig.host(text, at: 260, fromDocumentStart: false)).acceptance
            == accepted(text, fromDocumentStart: false))
        rig.type("👍🏽")
        let expected = try #require(rig.request.expected)
        #expect(expected.selection == ContextSelection(location: 264, length: 0))
        #expect(expected.context.prefix.utf16.count == 256)
        #expect(expected.context.prefix.hasSuffix("👍🏽"))
        #expect(rig.read(rig.host(text + "👍🏽", at: 264, fromDocumentStart: false))
            == Verdict(.transitionConfirmed, accepted(text + "👍🏽", fromDocumentStart: false)))
    }

    /// A caret delta that overflows the anchored location gives no expectation and drops the anchor; output stays
    /// awaited.
    @Test func overflowingAnchorGivesNoExpectation() {
        var rig = ContextRig()
        rig.read(rig.host("abc", at: Int.max - 2, fromDocumentStart: false))
        rig.type("👍🏽")
        #expect(rig.request.expected == nil)
        // Back at the anchored location the delta fits again, but the anchor is gone.
        rig.press(.backspace)
        #expect(rig.projection.caretDeltaUTF16 == 0)
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("abc", at: Int.max - 2, fromDocumentStart: false)) == Verdict(.settled, .ignored))
    }

    /// Typing over a selection puts the caret at its start plus the inserted units: selection(10,5) + X -> (11,0).
    @Test func selectionConsumptionUsesStartPlusInsertedUTF16() throws {
        var rig = ContextRig()
        #expect(rig.read(rig.host("0123456789", at: 10, selecting: 5)).acceptance == accepted("0123456789"))
        #expect(rig.gate.hasSelection)
        rig.type("X")
        #expect(!rig.gate.hasSelection)
        let expected = try #require(rig.request.expected)
        #expect(expected.selection == ContextSelection(location: 11, length: 0))
        #expect(expected.context == TextContext(prefix: "0123456789X", startsAtDocumentStart: true))
    }

    /// A sample of generation 1 arriving after the invalidation to generation 2 is ignored and keeps the newer anchor.
    @Test func staleTicketCannotChangeAnchor() throws {
        var rig = ContextRig()
        let first = rig.request
        #expect(first.ticket.generation == 1)
        rig.gate.invalidate(processID: contextProcess, awaitingHostChange: false)
        rig.issue()
        #expect(rig.request.ticket.generation == 2)
        #expect(rig.read(rig.host("hello", at: 5)).acceptance == accepted("hello"))

        let late = rig.host("hello wor", at: 9, ticket: first.ticket)
        var readerPrior: ContextSample?
        let sample = try #require(ContextEvidence.publish(
            before: late, after: late, expected: first.expected, isLatest: true, priorActual: &readerPrior
        ))
        #expect(sample.evidence == .settled)
        #expect(!rig.gate.isCurrent(first.ticket))
        #expect(rig.deliver(sample) == .ignored)
        rig.keyUp()
        #expect(rig.request.expected == ContextExpectation(
            target: contextField, selection: ContextSelection(location: 5, length: 0),
            context: TextContext(prefix: "hello", startsAtDocumentStart: true)
        ))
    }

    /// After `toi` is accepted with no output pending, the host showing `tai` at location 3 is a mismatch; the
    /// mismatching sample is not used as an anchor in the same pass.
    @Test func postAnchorSuffixMismatchDropsOwnership() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        #expect(rig.read(rig.host("toi", at: 3)) == Verdict(.transitionConfirmed, accepted("toi")))

        // A value notification reads the same request again after the host changed the owned text.
        let changed = rig.host("tai", at: 3)
        #expect(!rig.session.canSynchronizeContext(changed.context))
        #expect(rig.read(changed) == Verdict(.transitionConfirmed, .mismatch))
        rig.keyUp()
        #expect(rig.request.expected?.context.prefix == "toi")

        // The core then resets and invalidates; only the next read of that state anchors, owning nothing.
        _ = rig.session.handle(.reset)
        rig.gate.invalidate(processID: contextProcess, awaitingHostChange: false)
        rig.issue()
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("tai", at: 3)) == Verdict(.settled, accepted("tai")))
        #expect(!rig.projection.hasOwnedSuffix)
    }

    /// The first request of a ticket has a value; the same ticket again, a command result, or an unavailable read
    /// issue nothing; a physical key-up moves the watermark for a new request. No process, no request.
    @Test func repeatedTicketDoesNotScheduleReadLoop() throws {
        var gate = ContextGate()
        let projection = TypingSession().contextProjection
        #expect(gate.request(projection: projection) == nil)
        gate.invalidate(processID: nil, awaitingHostChange: false)
        #expect(gate.request(projection: projection) == nil)

        var rig = ContextRig()
        let first = rig.request
        #expect(rig.gate.request(projection: rig.projection) == nil)
        #expect(rig.read(rig.host("", at: 0)).acceptance == accepted(""))
        #expect(rig.gate.request(projection: rig.projection) == nil)
        rig.gate.markUnavailable()
        #expect(rig.gate.request(projection: rig.projection) == nil)

        rig.gate.noteInput()
        let issued = rig.gate.request(projection: rig.projection)
        let next = try #require(issued)
        #expect(next.ticket == ContextTicket(
            generation: first.ticket.generation, watermark: first.ticket.watermark + 1, processID: contextProcess
        ))
        #expect(rig.gate.request(projection: rig.projection) == nil)
    }

    // MARK: Recovery

    /// Unavailable drops the anchor: the next request has no expectation, a settled read with no output pending
    /// anchors again, and the request after a physical event expects that anchor. Output already pending stays
    /// awaited through unavailable, so a settled read is then ignored.
    @Test func unavailableDropsAnchorThenSettledSampleReanchors() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        #expect(rig.read(rig.host("toi", at: 3)).acceptance == accepted("toi"))

        rig.unavailable()
        rig.keyUp()
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("toi", at: 3)) == Verdict(.settled, accepted("toi")))
        rig.keyUp()
        #expect(rig.request.expected == ContextExpectation(
            target: contextField, selection: ContextSelection(location: 3, length: 0),
            context: TextContext(prefix: "toi", startsAtDocumentStart: true)
        ))

        rig.type("s")
        rig.unavailable()
        rig.keyUp()
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("tói", at: 3)) == Verdict(.settled, .ignored))
    }

    /// After a click the hook saw, reads of the unchanged state are ignored however often they repeat; a confirmed
    /// transition of the range anchors.
    @Test func pendingClickRejectsSettledReanchor() {
        var rig = ContextRig()
        rig.read(rig.host("hello", at: 5))
        rig.click()
        #expect(rig.request.expected == nil)
        #expect(rig.read(rig.host("hello", at: 5)) == Verdict(.settled, .ignored))
        rig.keyUp()
        #expect(rig.read(rig.host("hello", at: 5)) == Verdict(.settled, .ignored))
        #expect(rig.read(rig.host("he", at: 2)) == Verdict(.transitionConfirmed, accepted("he")))
    }

    /// Notifications for the session's own output read the latest request again: states before and after the host
    /// applies a key are ignored or accepted, never a mismatch; a stale read changes nothing; outside pending output a
    /// divergence is a mismatch.
    @Test func selfGeneratedNotificationsNeverMismatch() throws {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        var shown = ""
        for character in "toi" {
            let unapplied = shown
            rig.type(String(character))
            shown.append(character)
            #expect(rig.read(rig.host(unapplied, at: unapplied.utf16.count)) == Verdict(.settled, .ignored))
            #expect(rig.read(rig.host(shown, at: shown.utf16.count)) == Verdict(.transitionConfirmed, accepted(shown)))
            #expect(rig.read(rig.host(shown, at: shown.utf16.count)) == Verdict(.settled, accepted(shown)))
        }

        let old = rig.request.ticket
        rig.type("s")
        var readerPrior = rig.prior
        let stale = try #require(ContextEvidence.publish(
            before: rig.host("toi", at: 9, ticket: old), after: rig.host("toi", at: 9, ticket: old),
            expected: nil, isLatest: true, priorActual: &readerPrior
        ))
        #expect(rig.deliver(stale) == .ignored)
        #expect(rig.read(rig.host("tói", at: 3)).acceptance == accepted("tói"))

        #expect(rig.read(rig.host("tóa", at: 3)) == Verdict(.transitionConfirmed, .mismatch))
    }

    /// With no output pending, the host moving the caret on its own after `toi` is a confirmed transition and a
    /// mismatch, forwards or backwards and on a settled re-read; with output pending the same sample is ignored.
    /// Each sample here is judged against the same anchor; the core's reset after a mismatch is not modelled.
    @Test func stableRangeMoveOutsidePendingIsMismatch() {
        var rig = ContextRig()
        rig.read(rig.host("", at: 0))
        rig.type("toi")
        #expect(rig.read(rig.host("toi", at: 3)).acceptance == accepted("toi"))
        let moved = rig.host("toi hôm nay", at: 11)
        #expect(rig.read(moved) == Verdict(.transitionConfirmed, .mismatch))
        #expect(rig.read(moved) == Verdict(.settled, .mismatch))
        #expect(rig.read(rig.host("t", at: 1)) == Verdict(.transitionConfirmed, .mismatch))

        var pending = ContextRig()
        pending.read(pending.host("", at: 0))
        pending.type("toi")
        #expect(pending.read(pending.host("toi hôm nay", at: 11)) == Verdict(.transitionConfirmed, .ignored))
    }
}
