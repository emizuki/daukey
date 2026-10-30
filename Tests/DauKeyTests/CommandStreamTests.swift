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
        let typist = Typist(executor: typing.executor, enabled: true, settings: TypingSettings(), appMemory: [:],
                            rules: RuleTables(), snapshots: snapshots.continuation)
        commands.continuation.yield(.appActivated(bundleID: "app.a", processID: nil, inlineCompletionApp: false))
        commands.continuation.yield(.settings(.enabled(false)))
        commands.continuation.yield(.appActivated(bundleID: "app.b", processID: nil, inlineCompletionApp: false))
        commands.continuation.yield(.settings(.enabled(true)))
        commands.continuation.yield(.appActivated(bundleID: "app.a", processID: nil, inlineCompletionApp: false))
        commands.continuation.finish()
        await drainCommands(commands.stream, into: typist)
        snapshots.continuation.finish()
        var states: [Snapshot] = []
        for await snapshot in snapshots.stream { states.append(snapshot) }
        #expect(states.map(\.enabled) == [true, false, false, true, false])
        #expect(states.last?.appMemory == ["app.a": false, "app.b": true])
    }

    /// Each command changes only its own setting, in order, without resetting the others.
    @Test @MainActor func settingsCommandsApplyFieldByField() async {
        let commands = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshots = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, settings: TypingSettings(), appMemory: [:],
                            rules: RuleTables(), snapshots: snapshots.continuation)
        let shortcut = ShortcutConfig(modifiers: [.command], keyCode: 0x01)
        for change: SettingsChange in [
            .inputMethod(.vni), .toneStyle(.modern), .spelling(.check), .allowForeignConsonants(true),
            .autoCapitalize(true), .perAppSwitching(false), .soundEnabled(true), .shortcut(shortcut),
        ] {
            commands.continuation.yield(.settings(change))
        }
        commands.continuation.yield(.replaceRules(RuleTables(macros: [MacroRule(trigger: "vn", replacement: "VN")])))
        commands.continuation.finish()
        await drainCommands(commands.stream, into: typist)
        snapshots.continuation.finish()
        var last: Snapshot?
        for await snapshot in snapshots.stream { last = snapshot }
        #expect(last?.settings == TypingSettings(
            options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .check, allowForeignConsonants: true),
            session: SessionSettings(autoCapitalize: true), shortcut: shortcut, perAppSwitching: false,
            soundEnabled: true
        ))
        #expect(last?.enabled == true)
    }

    /// Commands schedule a context read for a new ticket, except while V/E is off.
    @Test @MainActor func commandsScheduleNoReadsWhileDisabled() async {
        let snapshots = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let reads = ScheduledReads()
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: true, settings: TypingSettings(), appMemory: [:],
                            rules: RuleTables(), snapshots: snapshots.continuation,
                            readContext: { reads.append($0) })
        await typist.handle(.appActivated(bundleID: "app.a", processID: 7, inlineCompletionApp: false))
        await typist.handle(.settings(.enabled(false)))
        await typist.handle(.appActivated(bundleID: "app.b", processID: 8, inlineCompletionApp: false))
        await typist.handle(.settings(.soundEnabled(true)))
        await typist.handle(.reset)
        await typist.handle(.inputSourceChanged)
        #expect(reads.processIDs == [7])
        await typist.handle(.settings(.enabled(true)))
        #expect(reads.processIDs == [7, 8])
    }
}

/// The context reads a Typist scheduled, recorded from the typing thread.
private final class ScheduledReads: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [ContextRequest] = []

    func append(_ request: ContextRequest) {
        lock.withLock { requests.append(request) }
    }

    var processIDs: [Int32] { lock.withLock { requests.map(\.ticket.processID) } }
}
