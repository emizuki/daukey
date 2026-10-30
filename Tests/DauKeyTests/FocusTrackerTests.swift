import Testing
@testable import DauKey

/// What saw the focused element: a read of the context or a focus notification. Elements stand for AX elements
/// compared by `CFEqual`.
private enum Sight {
    case read(Int)
    case notified(Int)
}

/// Whether each sight, in order, reports a move of focus to a fresh tracker.
private func reports(_ sights: [Sight]) -> [Bool] {
    var focus = FocusTracker<Int>()
    return sights.map { sight in
        switch sight {
        case .read(let element): focus.read(element)
        case .notified(let element): focus.notified(element)
        }
    }
}

@Suite struct FocusTrackerTests {
    /// A read that finds another element than the one last seen reports the move; the focus notification for that
    /// element, arriving afterwards, and later reads report nothing more.
    @Test func readSeeingNewElementReportsOnceAndNotificationStaysQuiet() {
        #expect(reports([.read(1), .read(1), .read(2), .notified(2), .read(2)])
            == [false, false, true, false, false])
    }

    /// A focus notification reports the move once; a repeated notification and the next reads of that element report
    /// nothing more.
    @Test func notificationReportsOnceAndReadStaysQuiet() {
        #expect(reports([.read(1), .notified(2), .notified(2), .read(2), .notified(2)])
            == [false, true, false, false, false])
    }

    /// The first element a read sees after attaching is where focus already was; a first notification is a move.
    @Test func firstReadIsNotAChangeButFirstNotificationIs() {
        #expect(reports([.read(1)]) == [false])
        #expect(reports([.notified(1), .read(1)]) == [true, false])
    }

    /// Moving away and back is two moves, whichever path sees each.
    @Test func roundTripReportsEachMove() {
        #expect(reports([.read(1), .notified(2), .notified(1), .read(1), .read(2), .read(1), .notified(1)])
            == [false, true, true, false, true, true, false])
    }
}
