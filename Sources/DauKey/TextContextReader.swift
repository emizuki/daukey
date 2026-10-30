import ApplicationServices
import CoreFoundation
import Foundation
import DauKeyEngine
import DauKeyHook

/// Reads the text before the caret of the focused element of the requested process, on a thread of its own.
///
/// That thread's run loop owns every AX element and observer and the element identities handed out, so AX calls never
/// run on the typing thread or the main actor, and `request` never waits for one. Requests coalesce: one read runs at
/// a time, always for the latest request. A value or selection notification reads the latest request again, without
/// a new ticket. A change of the focused element delivers `invalidated` once, whether the focus notification or a read
/// sees it first; that read publishes no sample. `deliver` runs on the reader's thread; the text read goes only to it,
/// and the one prior observation is all that is kept.
///
/// The scheduling state is guarded by `lock`; everything else is touched only on the reader's thread.
final class TextContextReader: @unchecked Sendable {
    /// Starting timeout for each AX messaging call (spec §7); to be confirmed by measurement.
    private static let messagingTimeout: Float = 0.05
    /// Units read before the bounded prefix, so that a character cut by the start of the read is not kept.
    private static let leadingSlackUTF16 = 32
    /// Without both, changes of the text or the caret go unseen and the element's context is unavailable.
    private static let textNotifications = [kAXValueChangedNotification, kAXSelectedTextChangedNotification]

    private struct AttachedApp {
        let processID: Int32
        let element: AXUIElement
        let observer: AXObserver
    }

    private struct FocusedElement {
        let element: AXUIElement
        let id: UInt64
        /// An editable, non-secure element of the attached process whose text notifications are registered.
        let readable: Bool
        /// Whether the element answers for its list of selected ranges; nil until asked.
        var listsRanges: Bool?
    }

    private enum ReadFailure: Error {
        /// The element's context cannot be read.
        case unavailable
        /// Focus moved to another element since the element last seen.
        case focusChanged
    }

    private let deliver: @Sendable (ContextObservation) -> Void

    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var latest: ContextRequest?
    /// Grows with every request and every notification that asks to read the latest request again.
    private var latestSerial: UInt64 = 0
    /// The serial of the read started last.
    private var readSerial: UInt64 = 0
    private var readScheduled = false
    private var stopped = false

    private var app: AttachedApp?
    /// The element focus was last seen on, by a read or a focus notification, in the attached app.
    private var focus = FocusTracker<AXUIElement>()
    /// What is known of the focused element once a read used it; nil or the element `focus` last saw.
    private var focused: FocusedElement?
    private var nextElementID: UInt64 = 1
    private var priorActual: ContextSample?

    init(deliver: @escaping @Sendable (ContextObservation) -> Void) {
        self.deliver = deliver
    }

    /// Starts the reader's thread and returns once its run loop takes reads.
    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            // Keeps the run loop running while no observer source is attached.
            let keepalive = CFRunLoopSourceCreate(nil, 0, &context)!
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, keepalive, .defaultMode)
            lock.withLock { runLoop = loop }
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, keepalive, .defaultMode)
        }
        thread.name = "DauKey context"
        thread.start()
        ready.wait()
        let loop = lock.withLock { stopped || latest == nil ? nil : schedule() }
        if let loop { wake(loop) }
    }

    /// Makes `request` the latest one and schedules a read unless one is already scheduled.
    func request(_ request: ContextRequest) {
        let loop = lock.withLock { () -> CFRunLoop? in
            guard !stopped else { return nil }
            latest = request
            latestSerial += 1
            return schedule()
        }
        if let loop { wake(loop) }
    }

    /// Stops reading; the observers and their source are removed on the reader's thread, which then ends.
    func stop() {
        let loop = lock.withLock { () -> CFRunLoop? in
            stopped = true
            latest = nil
            return runLoop
        }
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            detach()
            priorActual = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop)
    }

    // MARK: Scheduling

    /// Marks a read as scheduled; the run loop to wake, or nil when one already is. The caller holds `lock`.
    private func schedule() -> CFRunLoop? {
        guard !readScheduled, let runLoop else { return nil }
        readScheduled = true
        return runLoop
    }

    private func wake(_ loop: CFRunLoop) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in drain() }
        CFRunLoopWakeUp(loop)
    }

    /// Reads until the latest request has been read since it last changed. Only a read that is still the latest when
    /// it finishes is delivered or becomes the prior observation, except a change of focus: the read that sees it is
    /// the only one to report it.
    private func drain() {
        while case let (request, serial)? = nextRead() {
            let reads: (before: ContextSample, after: ContextSample)
            do throws(ReadFailure) {
                reads = try read(request.ticket)
            } catch .focusChanged {
                if lock.withLock({ !stopped }) { deliver(.invalidated(request.ticket)) }
                continue
            } catch {
                if lock.withLock({ !stopped && serial == latestSerial }) { deliver(.unavailable(request.ticket)) }
                continue
            }
            let isLatest = lock.withLock { !stopped && serial == latestSerial }
            if let sample = ContextEvidence.publish(
                before: reads.before, after: reads.after, expected: request.expected, isLatest: isLatest,
                priorActual: &priorActual
            ) {
                deliver(.sample(sample))
            }
        }
    }

    private func nextRead() -> (ContextRequest, UInt64)? {
        lock.withLock {
            guard !stopped, let latest, readSerial != latestSerial else {
                readScheduled = false
                return nil
            }
            readSerial = latestSerial
            return (latest, latestSerial)
        }
    }

    /// On the reader's thread, between reads.
    fileprivate func handle(_ notification: String, from element: AXUIElement) {
        if notification == kAXFocusedUIElementChangedNotification {
            guard focus.notified(element) else { return }
            forgetFocus()
            // A request for another app is read from that app afresh.
            let ticket = lock.withLock { stopped ? nil : latest?.ticket }
            if let ticket, ticket.processID == app?.processID { deliver(.invalidated(ticket)) }
            return
        }
        let loop = lock.withLock { () -> CFRunLoop? in
            guard !stopped, latest != nil else { return nil }
            latestSerial += 1
            return schedule()
        }
        if let loop { wake(loop) }
    }

    // MARK: Reading

    /// Two bounded reads of the focused element of the ticket's process, for the producer to compare.
    private func read(
        _ ticket: ContextTicket
    ) throws(ReadFailure) -> (before: ContextSample, after: ContextSample) {
        let app = try attach(ticket.processID)
        let before = try snapshot(ticket, in: app)
        let after = try snapshot(ticket, in: app)
        return (before, after)
    }

    /// The focused element, its one selected range, and the bounded text before that range. Its evidence is set by
    /// the producer.
    private func snapshot(_ ticket: ContextTicket, in app: AXUIElement) throws(ReadFailure) -> ContextSample {
        guard let object = copy(kAXFocusedUIElementAttribute, of: app), CFGetTypeID(object) == AXUIElementGetTypeID()
        else { throw .unavailable }
        let element = unsafeDowncast(object, to: AXUIElement.self)
        let id = try identify(element, in: ticket.processID)
        let selection = try selectedRange(of: element)
        return ContextSample(
            ticket: ticket, target: ContextTarget(processID: ticket.processID, elementID: id), selection: selection,
            context: try prefix(of: element, before: selection.location), evidence: .unconfirmed
        )
    }

    /// The identity of the focused element; one that newly became focused gets a new identity and is observed. Focus
    /// having moved since the element last seen ends the read.
    private func identify(_ element: AXUIElement, in processID: Int32) throws(ReadFailure) -> UInt64 {
        if focus.read(element) {
            forgetFocus()
            throw .focusChanged
        }
        if let focused, CFEqual(focused.element, element) {
            guard focused.readable else { throw .unavailable }
            return focused.id
        }
        forgetFocus()
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let id = nextElementID
        nextElementID += 1
        let readable = isEditable(element, in: processID) && observeText(of: element)
        focused = FocusedElement(element: element, id: id, readable: readable)
        guard readable else { throw .unavailable }
        return id
    }

    /// Whether `element` is an editable field that is not secure, in `processID`, whose observer would see its
    /// notifications.
    private func isEditable(_ element: AXUIElement, in processID: Int32) -> Bool {
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == processID else { return false }
        var subrole: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) {
        case .success: if subrole as? String == kAXSecureTextFieldSubrole { return false }
        case .attributeUnsupported, .noValue: break
        default: return false
        }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    /// The one selected range; several selections have no single caret.
    private func selectedRange(of element: AXUIElement) throws(ReadFailure) -> ContextSelection {
        if focused?.listsRanges != false {
            var ranges: CFTypeRef?
            switch AXUIElementCopyAttributeValue(element, kAXSelectedTextRangesAttribute as CFString, &ranges) {
            case .success:
                guard let list = ranges as? [AnyObject], list.count == 1 else { throw .unavailable }
                focused?.listsRanges = true
                return try selection(from: list[0])
            case .attributeUnsupported, .noValue:
                focused?.listsRanges = false
            default:
                throw .unavailable
            }
        }
        guard let range = copy(kAXSelectedTextRangeAttribute, of: element) else { throw .unavailable }
        return try selection(from: range)
    }

    private func selection(from object: CFTypeRef) throws(ReadFailure) -> ContextSelection {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { throw .unavailable }
        let value = unsafeDowncast(object, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
              range.location >= 0, range.length >= 0
        else { throw .unavailable }
        return ContextSelection(location: range.location, length: range.length)
    }

    /// The text before `location`, at most `TextContext.maxUTF16` units cut at a character boundary.
    private func prefix(of element: AXUIElement, before location: Int) throws(ReadFailure) -> TextContext {
        let start = max(0, location - (TextContext.maxUTF16 + Self.leadingSlackUTF16))
        guard start < location else { return TextContext(prefix: "", startsAtDocumentStart: true) }
        var range = CFRange(location: start, length: location - start)
        var text: CFTypeRef?
        guard let parameter = AXValueCreate(.cfRange, &range),
              AXUIElementCopyParameterizedAttributeValue(
                  element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &text
              ) == .success,
              let string = text as? String,
              // Text of another length does not line up with the range the caret is in.
              string.utf16.count == range.length
        else { throw .unavailable }
        return TextContext(prefix: string, startsAtDocumentStart: start == 0)
    }

    private func copy(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    // MARK: Observers

    /// The application element of `processID`, observed for focus changes. A failure is not remembered: the next read
    /// tries again.
    private func attach(_ processID: Int32) throws(ReadFailure) -> AXUIElement {
        if let app, app.processID == processID { return app.element }
        detach()
        let element = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        var created: AXObserver?
        guard AXObserverCreate(processID, observerCallback, &created) == .success, let observer = created,
              add(kAXFocusedUIElementChangedNotification, on: element, to: observer)
        else { throw .unavailable }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        app = AttachedApp(processID: processID, element: element, observer: observer)
        return element
    }

    private func detach() {
        forgetFocus()
        focus = FocusTracker()
        guard let app else { return }
        AXObserverRemoveNotification(app.observer, app.element, kAXFocusedUIElementChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(app.observer), .defaultMode)
        self.app = nil
    }

    /// Registers the text notifications of `element`, all or none.
    private func observeText(of element: AXUIElement) -> Bool {
        guard let app else { return false }
        for (index, notification) in Self.textNotifications.enumerated()
        where !add(notification, on: element, to: app.observer) {
            for added in Self.textNotifications[..<index] {
                AXObserverRemoveNotification(app.observer, element, added as CFString)
            }
            return false
        }
        return true
    }

    private func forgetFocus() {
        guard let focused else { return }
        if focused.readable, let app {
            for notification in Self.textNotifications {
                AXObserverRemoveNotification(app.observer, focused.element, notification as CFString)
            }
        }
        self.focused = nil
    }

    private func add(_ notification: String, on element: AXUIElement, to observer: AXObserver) -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        switch AXObserverAddNotification(observer, element, notification as CFString, refcon) {
        case .success, .notificationAlreadyRegistered: return true
        default: return false
        }
    }
}

/// The element focus was last seen on, so that each move of focus is reported once, whether a focus notification or a
/// read sees it first.
struct FocusTracker<Element: Equatable> {
    private var element: Element?

    /// A focus notification names `element`: whether focus moved to it.
    mutating func notified(_ element: Element) -> Bool {
        guard self.element != element else { return false }
        self.element = element
        return true
    }

    /// A read finds `element` focused: whether focus moved to it from the element last seen. The first element seen
    /// is where focus already was.
    mutating func read(_ element: Element) -> Bool {
        defer { self.element = element }
        return self.element.map { $0 != element } ?? false
    }
}

/// Runs on the reader's thread, whose run loop holds the observer's source; the reader outlives its observers.
private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<TextContextReader>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, from: element)
}
