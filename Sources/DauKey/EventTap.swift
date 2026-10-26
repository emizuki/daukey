import CoreGraphics
import CoreFoundation
import DauKeyHook

final class EventTap {
    enum Kind { case typing, target }
    let port: CFMachPort
    private let source: CFRunLoopSource
    private let runLoop: CFRunLoop
    init?(runLoop: CFRunLoop, userInfo: UnsafeMutableRawPointer, kind: Kind) {
        let types: [CGEventType] = kind == .typing
            ? [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown] : [.keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: kind == .typing ? .cgSessionEventTap : .cgAnnotatedSessionEventTap,
            place: kind == .typing ? .headInsertEventTap : .tailAppendEventTap,
            options: kind == .typing ? .defaultTap : .listenOnly, eventsOfInterest: mask,
            callback: kind == .typing ? tapCallback : targetCallback, userInfo: userInfo),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return nil }
        self.port = port
        self.source = source
        self.runLoop = runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
    }
    var enabled: Bool { CGEvent.tapIsEnabled(tap: port) }
    func enable() { CGEvent.tapEnable(tap: port, enable: true) }
    func remove() {
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(port)
    }
}

enum TapDisposition: Sendable { case pass, swallow }
private let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let typist = Unmanaged<Typist>.fromOpaque(userInfo).takeUnretainedValue()
    // Borrowed only for the synchronous closure below; neither alias escapes it.
    // checkIsolated verifies that both are used only on the typing thread.
    nonisolated(unsafe) let callbackEvent = event
    nonisolated(unsafe) let callbackProxy = proxy
    let disposition = typist.assumeIsolated { isolated in
        isolated.handleTap(type: type, event: callbackEvent, proxy: callbackProxy)
    }
    return disposition == .pass ? Unmanaged.passUnretained(event) : nil
}

private let targetCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let typist = Unmanaged<Typist>.fromOpaque(userInfo).takeUnretainedValue()
    // Borrowed synchronously on the typing thread, just like the main callback.
    nonisolated(unsafe) let callbackEvent = event
    typist.assumeIsolated { isolated in
        isolated.handleTarget(type: type, event: callbackEvent)
    }
    return Unmanaged.passUnretained(event)
}

extension Modifiers {
    init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskSecondaryFn) { insert(.function) }
        if flags.contains(.maskAlphaShift) { insert(.capsLock) }
    }
}
