import CoreGraphics
import Testing
@testable import DauKey

@Suite struct SpotlightTargetsTests {
    @Test func resolvedPIDsAreCachedIncludingOrdinaryApps() {
        for bundleID in ["com.apple.Spotlight", "com.apple.campo", "com.apple.Safari"] {
            var targets = SpotlightTargets()
            var calls: [Int32] = []
            let expected = bundleID != "com.apple.Safari"
            #expect(targets.resolve(pid: 42) { calls.append($0); return bundleID } == expected)
            #expect(targets.resolve(pid: 42) { calls.append($0); return "different.app" } == expected)
            #expect(calls == [42])
        }
    }

    @Test func unresolvedPIDIsRetried() {
        var targets = SpotlightTargets()
        #expect(!targets.resolve(pid: 42) { _ in nil })
        #expect(targets.resolve(pid: 42) { _ in "com.apple.Spotlight" })
    }

    @Test func activationResolvesReusedPIDAgain() {
        var targets = SpotlightTargets()
        #expect(targets.resolve(pid: 42) { _ in "com.apple.Spotlight" })
        #expect(!targets.resolve(pid: 43) { _ in "com.apple.Safari" })
        targets.appActivated()
        #expect(!targets.resolve(pid: 42) { _ in "com.apple.Safari" })
        #expect(targets.resolve(pid: 43) { _ in "com.apple.campo" })
    }

    @Test func keyDownResolvesTheEventTargetPID() throws {
        var targets = SpotlightTargets()
        let event = try targetEvent(pid: 42)
        #expect(targets.decision(type: .keyDown, event: event) { $0 == 42 ? "com.apple.campo" : "other.app" } == true)
        let ordinary = try targetEvent(pid: 43)
        #expect(targets.decision(type: .keyDown, event: ordinary) { $0 == 43 ? "com.apple.Safari" : "com.apple.Spotlight" } == false)
    }

    @Test func markedAndNonKeyDownEventsPreserveTheCurrentTarget() throws {
        var targets = SpotlightTargets()
        let marked = try targetEvent(pid: 42, marker: 0x4441554B4559)
        #expect(targets.decision(type: .keyDown, event: marked) { _ in Issue.record("Marked event looked up its target"); return "com.apple.Spotlight" } == nil)
        let event = try targetEvent(pid: 42)
        for type: CGEventType in [.keyUp, .flagsChanged, .leftMouseDown] {
            #expect(targets.decision(type: type, event: event) { _ in Issue.record("Non-key-down event looked up its target"); return "com.apple.Spotlight" } == nil)
        }
        // Ignored events must not poison the PID cache, either.
        #expect(targets.decision(type: .keyDown, event: event) { _ in "com.apple.Safari" } == false)
    }

    @Test func disabledTapClearsTheTargetEvenForMarkedEvents() throws {
        var targets = SpotlightTargets()
        let event = try targetEvent(pid: 42)
        #expect(targets.decision(type: .keyDown, event: event) { _ in "com.apple.Spotlight" } == true)
        let marked = try targetEvent(pid: 42, marker: 0x4441554B4559)
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            #expect(targets.decision(type: type, event: marked) { _ in Issue.record("Disabled tap looked up its target"); return nil } == false)
        }
    }
}

private func targetEvent(pid: Int64, marker: Int64 = 0) throws -> CGEvent {
    let source = try #require(CGEventSource(stateID: .privateState))
    let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
    withExtendedLifetime(source) {}
    return event
}
