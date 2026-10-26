import Foundation
import Testing
import DauKeyEngine
import DauKeyHook
@testable import DauKey

@Suite(.timeLimit(.minutes(1))) struct CommandStreamTests {
    @Test @MainActor func yieldedCommandsReachTypistInOrder() async {
        let commands = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshots = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .unbounded)
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, options: Options(),
                            appMemory: [:], snapshots: snapshots.continuation)
        commands.continuation.yield(.appActivated("app.a"))
        commands.continuation.yield(.setEnabled(false))
        commands.continuation.yield(.appActivated("app.b"))
        commands.continuation.yield(.setEnabled(true))
        commands.continuation.yield(.appActivated("app.a"))
        commands.continuation.finish()
        await drainCommands(commands.stream, into: typist)
        snapshots.continuation.finish()
        var states: [Snapshot] = []
        for await snapshot in snapshots.stream { states.append(snapshot) }
        #expect(states.map(\.enabled) == [true, false, false, true, false])
        #expect(states.last?.appMemory == ["app.a": false, "app.b": true])
    }
    @Test func storedSettingsDefaultAndRoundTripIncludingFalse() {
        let name = "DauKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let empty = StoredSettings(defaults)
        #expect(empty.enabled)
        #expect(empty.options == Options())
        #expect(empty.appMemory.isEmpty)
        let snapshot = Snapshot(enabled: false,
            options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .off, allowForeignConsonants: true),
            appMemory: ["app.a": false, "app.b": true], tap: .running)
        StoredSettings.save(snapshot, to: defaults)
        let loaded = StoredSettings(defaults)
        #expect(!loaded.enabled)
        #expect(loaded.options == snapshot.options)
        #expect(loaded.appMemory == snapshot.appMemory)
        defaults.set("unknown", forKey: "inputMethod")
        defaults.set("unknown", forKey: "toneStyle")
        defaults.set("unknown", forKey: "spelling")
        let unknown = StoredSettings(defaults)
        #expect(unknown.options.inputMethod == .telex)
        #expect(unknown.options.toneStyle == .old)
        #expect(unknown.options.spelling == .checkAndRestore)
    }
}
