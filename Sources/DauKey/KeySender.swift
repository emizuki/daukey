import CoreGraphics
import DauKeyHook
import os

final class KeySender {
    static let marker: Int64 = 0x4441554B4559
    // Matches no physical key, so the user can never hold it while it is posted.
    static let textKeyCode: CGKeyCode = 0x6C
    private let source = CGEventSource(stateID: .privateState)
    private let logger = Logger(subsystem: "com.emizuki.daukey", category: "output")
    func post(_ steps: [OutputStep], proxy: CGEventTapProxy) -> Bool {
        guard let events = events(for: steps) else { return false }
        for event in events { event.tapPostEvent(proxy) }
        return true
    }
    func events(for steps: [OutputStep]) -> [CGEvent]? {
        guard let source else {
            logger.error("Could not create output event source")
            return nil
        }
        var events: [CGEvent] = []
        for step in steps {
            switch step {
            case .backspaces(let count):
                for _ in 0..<count {
                    guard let pair = pair(code: 0x33, text: nil, source: source) else { return nil }
                    events.append(pair.0)
                    events.append(pair.1)
                }
            case .selectBackward(let count):
                for _ in 0..<count {
                    guard let pair = pair(code: 0x7B, text: nil, flags: .maskShift, source: source) else { return nil }
                    events.append(pair.0)
                    events.append(pair.1)
                }
            case .text(let text):
                guard let pair = pair(code: Self.textKeyCode, text: text, source: source) else { return nil }
                events.append(pair.0)
                events.append(pair.1)
            }
        }
        return events
    }
    private func pair(code: CGKeyCode, text: String?, flags: CGEventFlags = [],
                      source: CGEventSource) -> (CGEvent, CGEvent)? {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            logger.error("Could not create output key events")
            return nil
        }
        if let text {
            let units = Array(text.utf16)
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            }
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        return (down, up)
    }
}
