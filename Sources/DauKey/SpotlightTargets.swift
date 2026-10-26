import CoreGraphics
import DauKeyHook

/// Target state belongs to key recipients, which can differ from the frontmost app.
struct SpotlightTargets {
    private var resolved: [Int32: Bool] = [:]

    mutating func appActivated() {
        resolved.removeAll(keepingCapacity: true)
    }

    mutating func resolve(pid: Int32, lookup: (Int32) -> String?) -> Bool {
        if let cached = resolved[pid] { return cached }
        guard let bundleID = lookup(pid) else { return false }
        let isSpotlight = SpotlightTarget.matches(bundleID: bundleID)
        resolved[pid] = isSpotlight
        return isSpotlight
    }

    /// Nil preserves the current flag; disabled taps take precedence over filtering.
    mutating func decision(type: CGEventType, event: CGEvent, lookup: (Int32) -> String?) -> Bool? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return false }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != KeySender.marker else { return nil }
        return resolve(pid: Int32(event.getIntegerValueField(.eventTargetUnixProcessID)), lookup: lookup)
    }
}
