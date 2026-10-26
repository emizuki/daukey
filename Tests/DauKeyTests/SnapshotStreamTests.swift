import Foundation
import Testing
import DauKeyEngine
import DauKeyHook
@testable import DauKey

@Suite(.timeLimit(.minutes(1))) struct SnapshotStreamTests {
    @Test @MainActor func changedSnapshotsArriveInOrderAndUnchangedCommandsYieldNothing() async {
        let pair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .unbounded)
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, options: Options(),
                            appMemory: [:], snapshots: pair.continuation)
        await typist.handle(.reset)
        await typist.handle(.reset)
        await typist.handle(.setEnabled(false))
        await typist.handle(.setEnabled(false))
        await typist.handle(.setEnabled(true))
        pair.continuation.finish()
        var enabled: [Bool] = []
        for await snapshot in pair.stream { enabled.append(snapshot.enabled) }
        #expect(enabled == [true, false, true])
    }
    @Test @MainActor func newestBufferAlwaysDeliversLastFullState() async {
        let pair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, options: Options(),
                            appMemory: [:], snapshots: pair.continuation)
        for index in 0..<100 { await typist.handle(.setEnabled(index % 2 == 0)) }
        await typist.handle(.appActivated("last.app", chromiumBrowser: false))
        pair.continuation.finish()
        var received: [Snapshot] = []
        for await snapshot in pair.stream { received.append(snapshot) }
        #expect(received.count == 1)
        #expect(received.last?.enabled == false)
        #expect(received.last?.appMemory == ["last.app": false])
    }
}
