import Foundation
import Testing
import DauKeyEngine
import DauKeyHook
@testable import DauKey

@Suite(.timeLimit(.minutes(1))) struct SnapshotStreamTests {
    @Test @MainActor func changedSnapshotsArriveInOrderAndUnchangedCommandsYieldNothing() async {
        let pair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .unbounded)
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, settings: TypingSettings(), appMemory: [:],
                            rules: RuleTables(), snapshots: pair.continuation)
        await typist.handle(.reset)
        await typist.handle(.reset)
        await typist.handle(.settings(.enabled(false)))
        await typist.handle(.settings(.enabled(false)))
        await typist.handle(.settings(.enabled(true)))
        pair.continuation.finish()
        var enabled: [Bool] = []
        for await snapshot in pair.stream { enabled.append(snapshot.enabled) }
        #expect(enabled == [true, false, true])
    }
    @Test @MainActor func newestBufferAlwaysDeliversLastFullState() async {
        let pair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, settings: TypingSettings(), appMemory: [:],
                            rules: RuleTables(), snapshots: pair.continuation)
        for index in 0..<100 { await typist.handle(.settings(.enabled(index % 2 == 0))) }
        await typist.handle(.appActivated(bundleID: "last.app", processID: nil, inlineCompletionApp: false))
        pair.continuation.finish()
        var received: [Snapshot] = []
        for await snapshot in pair.stream { received.append(snapshot) }
        #expect(received.count == 1)
        #expect(received.last?.enabled == false)
        #expect(received.last?.appMemory == ["last.app": false])
    }
    /// The capture session stays in every later snapshot, and an end for another session leaves it alone.
    @Test @MainActor func captureSessionSurvivesCoalescing() async {
        let pair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, settings: TypingSettings(), appMemory: [:],
                            rules: RuleTables(), snapshots: pair.continuation)
        await typist.handle(.beginShortcutCapture(id: 4))
        await typist.handle(.settings(.soundEnabled(true)))
        await typist.handle(.endShortcutCapture(id: 3))
        pair.continuation.finish()
        var received: [Snapshot] = []
        for await snapshot in pair.stream { received.append(snapshot) }
        #expect(received.last?.shortcutCapture == CaptureSnapshot(id: 4, phase: .recording))
        #expect(received.last?.settings.soundEnabled == true)
    }
}
