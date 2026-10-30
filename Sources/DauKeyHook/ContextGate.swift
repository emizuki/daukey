import DauKeyEngine

/// When a context read was requested: the gate's invalidation generation, its input watermark, and the process the
/// read targets.
public struct ContextTicket: Sendable, Equatable {
    public let generation: UInt64
    public let watermark: UInt64
    public let processID: Int32

    public init(generation: UInt64, watermark: UInt64, processID: Int32) {
        self.generation = generation
        self.watermark = watermark
        self.processID = processID
    }

    /// Whether this ticket was issued after `other`; both counters only grow.
    func isNewer(than other: ContextTicket) -> Bool {
        (generation, watermark) > (other.generation, other.watermark)
    }
}

/// A text element: its process and the opaque identity the reader gave it while it stayed focused.
public struct ContextTarget: Sendable, Equatable {
    public let processID: Int32
    public let elementID: UInt64

    public init(processID: Int32, elementID: UInt64) {
        self.processID = processID
        self.elementID = elementID
    }
}

/// A selected range in UTF-16 units; length 0 is an insertion point.
public struct ContextSelection: Sendable, Equatable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// What the session expects the host to show: the element, the selected range, and the text before it.
public struct ContextExpectation: Sendable, Equatable {
    public let target: ContextTarget
    public let selection: ContextSelection
    public let context: TextContext

    public init(target: ContextTarget, selection: ContextSelection, context: TextContext) {
        self.target = target
        self.selection = selection
        self.context = context
    }
}

/// How a read relates to the reader's previous consistent observation.
public enum AnchorEvidence: Sendable, Equatable {
    /// The read is consistent and is the first observation, or the actual state did not change.
    case settled
    /// The read is consistent and the actual state changed; this does not show which output the host applied.
    case transitionConfirmed
    /// The two reads of the request disagree, or the previous observation is newer than the read.
    case unconfirmed
}

/// The host's state read for a ticket: the focused element, its selected range, and the text before that range.
public struct ContextSample: Sendable, Equatable {
    public let ticket: ContextTicket
    public let target: ContextTarget
    public let selection: ContextSelection
    public let context: TextContext
    public let evidence: AnchorEvidence

    public init(
        ticket: ContextTicket, target: ContextTarget, selection: ContextSelection, context: TextContext,
        evidence: AnchorEvidence
    ) {
        self.ticket = ticket
        self.target = target
        self.selection = selection
        self.context = context
        self.evidence = evidence
    }

    /// Whether the two samples show the same element, range, and text; tickets and evidence are not compared.
    func hasSameActual(as other: ContextSample) -> Bool {
        target == other.target && selection == other.selection && context == other.context
    }
}

/// What the reader delivers for a ticket.
public enum ContextObservation: Sendable, Equatable {
    case sample(ContextSample)
    /// The focused element changed.
    case invalidated(ContextTicket)
    /// The focused element's context cannot be read.
    case unavailable(ContextTicket)
}

/// A read to perform: the ticket its result must carry and what the session expects, when that is known.
public struct ContextRequest: Sendable, Equatable {
    public let ticket: ContextTicket
    public let expected: ContextExpectation?

    public init(ticket: ContextTicket, expected: ContextExpectation?) {
        self.ticket = ticket
        self.expected = expected
    }
}

/// The gate's verdict on a sample.
public enum ContextAcceptance: Sendable, Equatable {
    /// The sample is the new anchor; the session synchronizes with its context.
    case accepted(TextContext)
    /// The sample is stale, unconfirmed, or may lag behind output the host has not applied; nothing changes.
    case ignored
    /// The host diverged from what the session owns.
    case mismatch
}

/// Classifies the reads made for one request against the reader's previous consistent observation.
public enum ContextEvidence {
    /// `before` and `after` are two bounded reads made for the same request; their own evidence is not used. Of
    /// `expected`, only whether it is known matters: without it, text changing alone at the same element and range
    /// stays settled.
    public static func evaluate(
        priorActual: ContextSample?, before: ContextSample, after: ContextSample, expected: ContextExpectation?
    ) -> AnchorEvidence {
        guard before.ticket == after.ticket, before.hasSameActual(as: after) else { return .unconfirmed }
        guard let priorActual else { return .settled }
        if priorActual.ticket.isNewer(than: after.ticket) { return .unconfirmed }
        if priorActual.hasSameActual(as: after) { return .settled }
        if expected == nil, priorActual.target == after.target, priorActual.selection == after.selection {
            return .settled
        }
        return .transitionConfirmed
    }

    /// The sample a finished read publishes, or nil when a newer request superseded it while reading. A published
    /// consistent sample becomes `priorActual`; a superseded or unconfirmed read leaves it unchanged.
    public static func publish(
        before: ContextSample, after: ContextSample, expected: ContextExpectation?, isLatest: Bool,
        priorActual: inout ContextSample?
    ) -> ContextSample? {
        guard isLatest else { return nil }
        let sample = ContextSample(
            ticket: after.ticket, target: after.target, selection: after.selection, context: after.context,
            evidence: evaluate(priorActual: priorActual, before: before, after: after, expected: expected)
        )
        if sample.evidence != .unconfirmed { priorActual = sample }
        return sample
    }
}

/// Decides which host samples anchor the session's context, and issues the reads that check it.
///
/// The gate keeps the ticket counters, the anchored element and raw range, and whether output or a relocation still
/// waits for the host. The expected text and how far the caret moved come from the session's projection; the gate
/// keeps no copy of the owned text.
public struct ContextGate: Sendable {
    private struct Anchor: Sendable {
        let target: ContextTarget
        /// The raw range of the accepted sample; typed text replacing a selection sets its length to 0.
        var selection: ContextSelection
    }

    private var generation: UInt64 = 0
    private var watermark: UInt64 = 0
    /// The focused app's process; nil while unknown, and then no read is requested.
    private var processID: Int32?
    private var anchor: Anchor?
    /// Output was submitted, or the hook saw a relocation, and no sample has shown the host since.
    private var awaitingHost = false
    private var lastIssuedTicket: ContextTicket?

    public init() {}

    /// Whether the anchor is a selection that typed text has not replaced yet.
    public var hasSelection: Bool { (anchor?.selection.length ?? 0) > 0 }

    /// Starts a new generation for `processID`, the focused app's process or nil when unknown: earlier samples become
    /// stale and the anchor is dropped. `awaitingHostChange` waits for the host to show a relocation the hook saw;
    /// output the host was not seen to apply stays awaited either way.
    public mutating func invalidate(processID: Int32?, awaitingHostChange: Bool) {
        generation += 1
        self.processID = processID
        anchor = nil
        if awaitingHostChange { awaitingHost = true }
    }

    /// Records a physical input event; samples requested before it become stale.
    public mutating func noteInput() {
        watermark += 1
    }

    /// Records textual output the sender submitted: the host has yet to show it, and it replaced any selection.
    public mutating func didSubmit() {
        awaitingHost = true
        if let selection = anchor?.selection, selection.length > 0 {
            anchor?.selection = ContextSelection(location: selection.location, length: 0)
        }
    }

    /// Drops the anchor after the current context could not be read; output stays awaited.
    public mutating func markUnavailable() {
        anchor = nil
    }

    public func isCurrent(_ ticket: ContextTicket) -> Bool {
        ticket.generation == generation && ticket.watermark == watermark && ticket.processID == processID
    }

    /// A read for the current ticket, issued once per ticket; nil while the process is unknown or once this ticket
    /// was issued. The expectation is the anchor moved by the session's caret delta; without a delta, or when the
    /// move overflows, it is nil and the anchor is dropped.
    public mutating func request(projection: ContextProjection) -> ContextRequest? {
        guard let processID else { return nil }
        let ticket = ContextTicket(generation: generation, watermark: watermark, processID: processID)
        guard ticket != lastIssuedTicket else { return nil }
        lastIssuedTicket = ticket
        let expected = expectation(for: projection)
        if expected == nil { anchor = nil }
        return ContextRequest(ticket: ticket, expected: expected)
    }

    /// Judges a sample by the gate's current state, not by the state when its request was issued.
    ///
    /// `ownedSuffixMatches` says whether the sample's context ends with the text the session owns. The core sets
    /// `allowsInlineSuggestion` only for an app with the inline-suggestion workaround whose owned text the sample ends
    /// with; it then ignores a selected length where the location and known text match the expectation.
    public mutating func accept(
        _ sample: ContextSample, projection: ContextProjection, ownedSuffixMatches: Bool,
        allowsInlineSuggestion: Bool
    ) -> ContextAcceptance {
        guard isCurrent(sample.ticket), sample.evidence != .unconfirmed else { return .ignored }
        guard sample.target.processID == processID else { return .mismatch }
        if let expected = expectation(for: projection) {
            guard sample.target == expected.target else { return .mismatch }
            let knownText = Self.agree(sample.context, expected.context)
            let range = sample.selection == expected.selection
                || (allowsInlineSuggestion && knownText && sample.selection.location == expected.selection.location)
            if awaitingHost {
                // A sample that differs may still be on its way to the expected state.
                guard range, knownText else { return .ignored }
            } else {
                guard range, ownedSuffixMatches else { return .mismatch }
            }
        } else if awaitingHost {
            // Neither an unchanged state nor text the session does not own shows the host applied what it awaits.
            guard sample.evidence == .transitionConfirmed, ownedSuffixMatches else { return .ignored }
        } else {
            guard ownedSuffixMatches else { return .mismatch }
        }
        anchor = Anchor(target: sample.target, selection: sample.selection)
        awaitingHost = false
        return .accepted(sample.context)
    }

    private func expectation(for projection: ContextProjection) -> ContextExpectation? {
        guard let anchor, let delta = projection.caretDeltaUTF16 else { return nil }
        let (location, overflow) = anchor.selection.location.addingReportingOverflow(delta)
        guard !overflow, location >= 0 else { return nil }
        return ContextExpectation(
            target: anchor.target,
            selection: ContextSelection(location: location, length: anchor.selection.length),
            context: projection.context
        )
    }

    /// Whether two bounded prefixes agree where both are known: the shorter one ends the longer one, and one that
    /// starts at the document start leaves no text before it in the other.
    private static func agree(_ actual: TextContext, _ expected: TextContext) -> Bool {
        var actualCharacters = actual.prefix.reversed().makeIterator()
        var expectedCharacters = expected.prefix.reversed().makeIterator()
        while true {
            switch (actualCharacters.next(), expectedCharacters.next()) {
            case let (a?, e?): if a != e { return false }
            case (nil, nil): return actual.startsAtDocumentStart || !expected.startsAtDocumentStart
            case (nil, _?): return !actual.startsAtDocumentStart
            case (_?, nil): return !expected.startsAtDocumentStart
            }
        }
    }
}
