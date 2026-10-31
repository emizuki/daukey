import CoreGraphics
import DauKeyHook
import Testing
@testable import DauKey

@Suite struct KeySenderTests {
    @Test func mixedEventsPreservePairOrderAndLimitShiftToSelection() throws {
        let events = try #require(KeySender().events(for: [
            .backspaces(2), .text("a"), .selectBackward(2), .backspaces(1), .text("ế"),
        ], releasingBackspace: false))
        #expect(events.map(\.type) == [
            .keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp,
            .keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp,
        ])
        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
                == [0x33, 0x33, 0x33, 0x33, 0x6C, 0x6C, 0x7B, 0x7B, 0x7B, 0x7B, 0x33, 0x33, 0x6C, 0x6C])
        #expect(events.map(\.flags) == [[], [], [], [], [], [], .maskShift, .maskShift, .maskShift, .maskShift, [], [], [], []])
    }

    @Test func allEventKindsCarryTheRecursionMarker() throws {
        let events = try #require(KeySender().events(for: [.backspaces(1), .selectBackward(1), .text("ế")],
                                                     releasingBackspace: false))
        #expect(events.count == 6)
        for event in events {
            #expect(event.getIntegerValueField(.eventSourceUserData) == KeySender.marker)
        }
    }

    @Test func backspacesPostedWhileThePhysicalOneIsHeldStartWithItsRelease() throws {
        let events = try #require(KeySender().events(for: [.backspaces(2), .text("ồi")], releasingBackspace: true))
        #expect(events.map(\.type) == [.keyUp, .keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp])
        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0x33, 0x33, 0x33, 0x33, 0x33, 0x6C, 0x6C])
        for event in events {
            #expect(event.getIntegerValueField(.eventSourceUserData) == KeySender.marker)
        }
    }

    @Test func textPairsCarryUnicodeOnTheNonphysicalKey() throws {
        let events = try #require(KeySender().events(for: [.text("ế😀")], releasingBackspace: false))
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        for event in events {
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == 0x6C)
            var units = [UniChar](repeating: 0, count: 16)
            var count = 0
            event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &count, unicodeString: &units)
            #expect(Array(units.prefix(count)) == [0x1EBF, 0xD83D, 0xDE00])
        }
    }
}
