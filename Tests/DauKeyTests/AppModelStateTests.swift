import Foundation
import Testing
import DauKeyEngine
import DauKeyHook
@testable import DauKey

/// Runs `body` with a defaults suite no other test or app uses, removed afterwards.
@MainActor private func withDefaults(_ body: (UserDefaults) async -> Void) async {
    let name = "DauKeyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    await body(defaults)
    defaults.removePersistentDomain(forName: name)
}

/// The app model wired to a real core through the baseline streams: an unbounded FIFO of commands and a newest-only
/// snapshot buffer the core publishes to as the Typist does. Built the way the runtime boots: startup settings and the
/// rule editor's compiled tables come from the same store before the core exists. No event tap, thread or window.
@MainActor private final class Runtime {
    let model: AppModel
    private(set) var core: TypingCore
    private var commands: AsyncStream<Command>.AsyncIterator
    private let snapshots: AsyncStream<Snapshot>.Continuation
    private var published: Snapshot?
    /// What the focused field shows after typing.
    private(set) var text = ""

    init(defaults: UserDefaults, permissionGranted: Bool = true) {
        let store = PreferencesStore(defaults: defaults)
        let startup = store.load()
        let commandPair = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshotPair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let continuation = commandPair.continuation
        let rules = RuleEditorModel(store: store) { continuation.yield(.replaceRules($0)) }
        core = TypingCore(enabled: startup.runtime.enabled, settings: startup.runtime.settings,
                          appMemory: startup.runtime.appMemory, rules: rules.tables)
        model = AppModel(store: store, initial: startup, permissionGranted: permissionGranted,
                         commands: continuation, snapshots: snapshotPair.stream, rules: rules,
                         localization: LocalizationManager(language: startup.language, store: store))
        commands = commandPair.stream.makeAsyncIterator()
        snapshots = snapshotPair.continuation
    }

    var recorder: ShortcutRecorder { model.shortcutRecorder }

    /// Applies the next `count` commands in FIFO order, publishing after each one, and returns them.
    @discardableResult
    func drain(_ count: Int) async -> [Command] {
        var iterator = commands
        var drained: [Command] = []
        for _ in 0..<count {
            guard let command = await iterator.next(isolation: #isolation) else { break }
            drained.append(command)
            _ = core.handle(command)
            publish()
        }
        commands = iterator
        return drained
    }

    /// Lets the model take the newest buffered snapshot, as its consuming loop does.
    func consume(sourceLocation: SourceLocation = #_sourceLocation) async {
        let consumed = await model.consumeNextSnapshot()
        #expect(consumed, sourceLocation: sourceLocation)
    }

    /// Delivers an old snapshot again, as a late delivery would.
    func redeliver(_ snapshot: Snapshot) {
        snapshots.yield(snapshot)
    }

    func snapshot(with capture: CaptureSnapshot) -> Snapshot {
        let current = core.snapshot
        return Snapshot(enabled: current.enabled, settings: current.settings, appMemory: current.appMemory,
                        tap: current.tap, shortcutCapture: capture)
    }

    func flags(_ modifiers: Modifiers) {
        _ = core.flagsChanged(modifiers)
        publish()
    }

    /// Types each character with its key-down and key-up; the sender always succeeds.
    func type(_ keys: String) {
        for character in keys {
            let input = KeyInput(keyCode: character == " " ? 0x31 : 0, modifiers: [], characters: String(character))
            let result = core.keyDown(input)
            let steps: [OutputStep]
            let passes: Bool
            switch result.decision {
            case .pass: steps = []; passes = true
            case .swallow(let output): steps = output; passes = false
            case .passAfter(let output): steps = output; passes = true
            }
            for step in steps {
                switch step {
                case .backspaces(let count): text.removeLast(count)
                case .selectBackward(let count): text.removeLast(count)
                case .text(let inserted): text += inserted
                }
            }
            if result.requiresCommit { core.commitSent() }
            if passes { text.append(character) }
            _ = core.keyUp(input.keyCode)
            publish()
        }
    }

    private func publish() {
        let snapshot = core.snapshot
        guard snapshot != published else { return }
        published = snapshot
        snapshots.yield(snapshot)
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct AppModelStateTests {
    @Test func captureResultTraversesSnapshotOnce() async {
        await withDefaults { defaults in
            let runtime = Runtime(defaults: defaults)
            let recorder = runtime.recorder
            let first = ShortcutConfig(modifiers: [.control, .option])
            let second = ShortcutConfig(modifiers: [.command, .shift])
            var recorded: [ShortcutConfig] = []
            // The chord held when recording starts is not recorded.
            runtime.flags([.control, .shift])
            recorder.start { config in
                recorded.append(config)
                runtime.model.send(.settings(.shortcut(config)))
                // Recording again from the callback starts a new session.
                recorder.start { config in
                    recorded.append(config)
                    runtime.model.send(.settings(.shortcut(config)))
                }
            }
            #expect(await runtime.drain(1) == [.beginShortcutCapture(id: 1)])
            await runtime.consume()
            #expect(recorder.isRecording && recorder.hasMonitor)
            runtime.flags([])
            runtime.flags([.control, .option])
            runtime.flags([])
            let firstResult = runtime.core.snapshot
            #expect(firstResult.shortcutCapture == CaptureSnapshot(id: 1, phase: .recorded(first)))
            await runtime.consume()
            #expect(recorded == [first])
            #expect(await runtime.drain(3) == [
                .settings(.shortcut(first)), .beginShortcutCapture(id: 2), .endShortcutCapture(id: 1),
            ])
            #expect(runtime.core.snapshot.settings.shortcut == first)
            #expect(runtime.core.snapshot.shortcutCapture == CaptureSnapshot(id: 2, phase: .recording))
            await runtime.consume()
            #expect(recorder.isRecording && recorder.hasMonitor)

            // The first session's result delivered again neither fires nor touches the second session.
            runtime.redeliver(firstResult)
            await runtime.consume()
            #expect(recorded == [first])
            #expect(recorder.isRecording && recorder.hasMonitor)

            runtime.flags([.command, .shift])
            runtime.flags([])
            await runtime.consume()
            #expect(recorded == [first, second])
            #expect(!recorder.isRecording && !recorder.hasMonitor)
            #expect(await runtime.drain(2) == [.settings(.shortcut(second)), .endShortcutCapture(id: 2)])
            #expect(runtime.core.snapshot.settings.shortcut == second)
            #expect(runtime.core.snapshot.shortcutCapture == CaptureSnapshot(id: 2, phase: .inactive))
            await runtime.consume()
            #expect(recorded == [first, second])

            // Closing before the result is consumed applies nothing.
            recorder.start { config in
                recorded.append(config)
                runtime.model.send(.settings(.shortcut(config)))
            }
            #expect(await runtime.drain(1) == [.beginShortcutCapture(id: 3)])
            runtime.flags([.control, .command])
            runtime.flags([])
            recorder.stop()
            #expect(!recorder.isRecording && !recorder.hasMonitor)
            await runtime.consume()
            #expect(recorded == [first, second])
            #expect(await runtime.drain(1) == [.endShortcutCapture(id: 3)])
            #expect(runtime.core.snapshot.settings.shortcut == second)
        }
    }

    @Test func staleCaptureAcknowledgmentCannotArmNewSession() async {
        await withDefaults { defaults in
            let runtime = Runtime(defaults: defaults)
            let recorder = runtime.recorder
            var recorded: [ShortcutConfig] = []
            recorder.start { recorded.append($0) }
            #expect(await runtime.drain(1) == [.beginShortcutCapture(id: 1)])
            // Session 1 is waiting for its acknowledgment when the user starts over.
            recorder.stop()
            recorder.start { recorded.append($0) }
            await runtime.consume()
            #expect(recorder.isRecording && !recorder.hasMonitor)
            #expect(await runtime.drain(2) == [.endShortcutCapture(id: 1), .beginShortcutCapture(id: 2)])
            await runtime.consume()
            #expect(recorder.hasMonitor)

            // Late results of session 1, recorded or cancelled, neither fire, disarm nor cancel session 2.
            let config = ShortcutConfig(modifiers: [.control, .option])
            runtime.redeliver(runtime.snapshot(with: CaptureSnapshot(id: 1, phase: .recorded(config))))
            await runtime.consume()
            runtime.redeliver(runtime.snapshot(with: CaptureSnapshot(id: 1, phase: .inactive)))
            await runtime.consume()
            #expect(recorded.isEmpty)
            #expect(recorder.isRecording && recorder.hasMonitor)

            // An end for session 1 does not close the core's session 2.
            runtime.model.send(.endShortcutCapture(id: 1))
            await runtime.drain(1)
            #expect(runtime.core.snapshot.shortcutCapture == CaptureSnapshot(id: 2, phase: .recording))
            runtime.flags([.control, .option])
            runtime.flags([])
            await runtime.consume()
            #expect(recorded == [config])
        }
    }

    @Test func coalescedCapturePhasesStillDeliverResult() async {
        await withDefaults { defaults in
            let runtime = Runtime(defaults: defaults)
            let recorder = runtime.recorder
            let config = ShortcutConfig(modifiers: [.control, .option])
            var recorded: [ShortcutConfig] = []
            runtime.flags([.control, .shift])
            recorder.start { config in
                recorded.append(config)
                runtime.model.send(.settings(.shortcut(config)))
            }
            #expect(await runtime.drain(1) == [.beginShortcutCapture(id: 1)])
            #expect(runtime.core.snapshot.shortcutCapture.phase == .waitingForRelease)
            runtime.flags([])
            #expect(runtime.core.snapshot.shortcutCapture.phase == .recording)
            runtime.flags([.control, .option])
            runtime.flags([])
            // Other changes published before the model consumes keep the result.
            runtime.model.send(.settings(.soundEnabled(true)))
            await runtime.drain(1)
            #expect(runtime.core.snapshot.shortcutCapture == CaptureSnapshot(id: 1, phase: .recorded(config)))
            await runtime.consume()
            #expect(runtime.model.snapshot.settings.soundEnabled)
            #expect(recorded == [config])
            #expect(await runtime.drain(2) == [.settings(.shortcut(config)), .endShortcutCapture(id: 1)])
            await runtime.consume()
            #expect(recorded == [config])
            #expect(runtime.model.snapshot.settings.shortcut == config)
        }
    }

    @Test func resetAndRelaunchRestoreDefaultsButKeepRules() async {
        await withDefaults { defaults in
            await withDefaults { other in
                let seeded = PreferencesStore(defaults: defaults)
                let custom = RuntimePreferences(
                    enabled: false,
                    settings: TypingSettings(
                        options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .off,
                                         allowForeignConsonants: true),
                        session: SessionSettings(autoCapitalize: true),
                        shortcut: ShortcutConfig(modifiers: [.command], keyCode: 0x01), perAppSwitching: false,
                        soundEnabled: true
                    ),
                    appMemory: ["app.a": false]
                )
                let macros = [MacroEntry(trigger: "vn", replacement: "Việt Nam"), MacroEntry(trigger: "", replacement: "draft")]
                let exclusions = [ExclusionEntry(word: "been"), ExclusionEntry(word: "")]
                seeded.saveRuntime(custom)
                seeded.saveLanguage(.english)
                seeded.saveWelcomeShown(true)
                seeded.saveRules(macros: macros, exclusions: exclusions)

                let runtime = Runtime(defaults: defaults, permissionGranted: false)
                #expect(runtime.model.snapshot.enabled == false)
                #expect(runtime.model.snapshot.settings == custom.settings)
                #expect(runtime.model.localization.currentLanguage == .english)
                runtime.model.send(.appActivated(bundleID: "app.current", processID: 5, inlineCompletionApp: false))
                await runtime.drain(1)
                runtime.model.resetToDefaults()
                #expect(await runtime.drain(1) == [.resetToDefaults])
                await runtime.consume()
                #expect(runtime.model.snapshot.enabled)
                #expect(runtime.model.snapshot.settings == TypingSettings())
                #expect(runtime.model.snapshot.appMemory.isEmpty)
                #expect(runtime.model.localization.currentLanguage == .vietnamese)
                #expect(!runtime.model.permissionGranted)
                #expect(runtime.model.didShowWelcome)
                #expect(runtime.model.rules.macroEntries == macros)
                #expect(runtime.model.rules.exclusionEntries == exclusions)
                runtime.type("vn been ")
                #expect(runtime.text == "Việt Nam been ")

                let reloaded = PreferencesStore(defaults: defaults)
                let startup = reloaded.load()
                #expect(startup.runtime == RuntimePreferences())
                #expect(startup.language == .vietnamese)
                #expect(startup.didShowWelcome)
                let rules = reloaded.loadRules()
                #expect(rules.macros == macros)
                #expect(rules.exclusions == exclusions)

                // A second suite starts from its own defaults and leaves the first alone.
                let fresh = Runtime(defaults: other)
                #expect(fresh.model.snapshot.settings == TypingSettings())
                #expect(fresh.model.rules.macroEntries.isEmpty && fresh.model.rules.exclusionEntries.isEmpty)
                fresh.type("vn ")
                #expect(fresh.text == "vn ")
                fresh.model.resetToDefaults()
                await fresh.drain(1)
                await fresh.consume()
                #expect(PreferencesStore(defaults: defaults).loadRules().macros == macros)
                #expect(PreferencesStore(defaults: other).loadRules().macros.isEmpty)
            }
        }
    }

    @Test func resetDuringCaptureDisarmsRecorderImmediately() async {
        await withDefaults { defaults in
            let runtime = Runtime(defaults: defaults)
            let recorder = runtime.recorder
            var recorded: [ShortcutConfig] = []
            let config = ShortcutConfig(modifiers: [.control, .option])

            // Before the core acknowledged the session.
            recorder.start { recorded.append($0); runtime.model.send(.settings(.shortcut($0))) }
            runtime.model.resetToDefaults()
            #expect(!recorder.isRecording && !recorder.hasMonitor)
            #expect(await runtime.drain(3) == [
                .beginShortcutCapture(id: 1), .endShortcutCapture(id: 1), .resetToDefaults,
            ])
            #expect(runtime.core.snapshot.shortcutCapture == CaptureSnapshot(id: 1, phase: .inactive))
            runtime.redeliver(runtime.snapshot(with: CaptureSnapshot(id: 1, phase: .waitingForRelease)))
            await runtime.consume()
            #expect(!recorder.hasMonitor)
            runtime.redeliver(runtime.snapshot(with: CaptureSnapshot(id: 1, phase: .recorded(config))))
            await runtime.consume()
            #expect(recorded.isEmpty)
            runtime.model.send(.reset)
            #expect(await runtime.drain(1) == [.reset])
            #expect(runtime.core.snapshot.settings == TypingSettings())

            // While recording.
            recorder.start { recorded.append($0); runtime.model.send(.settings(.shortcut($0))) }
            #expect(await runtime.drain(1) == [.beginShortcutCapture(id: 2)])
            await runtime.consume()
            #expect(recorder.hasMonitor)
            runtime.model.resetToDefaults()
            #expect(!recorder.isRecording && !recorder.hasMonitor)
            #expect(await runtime.drain(2) == [.endShortcutCapture(id: 2), .resetToDefaults])
            runtime.flags([.control, .option])
            runtime.flags([])
            await runtime.consume()
            #expect(recorded.isEmpty)
            #expect(runtime.core.snapshot.shortcutCapture == CaptureSnapshot(id: 2, phase: .inactive))
            #expect(runtime.core.snapshot.settings == TypingSettings())
        }
    }

    @Test func persistedRulesAreActiveImmediatelyAfterRelaunch() async {
        await withDefaults { defaults in
            PreferencesStore(defaults: defaults).saveRules(
                macros: [MacroEntry(trigger: "vn", replacement: "Việt Nam")], exclusions: [ExclusionEntry(word: "been")]
            )
            let launched = Runtime(defaults: defaults)
            launched.type("vn been ")
            #expect(launched.text == "Việt Nam been ")
            launched.model.resetToDefaults()
            await launched.drain(1)
            await launched.consume()

            let relaunched = Runtime(defaults: defaults)
            relaunched.type("vn been ")
            #expect(relaunched.text == "Việt Nam been ")
        }
        await withDefaults { empty in
            let runtime = Runtime(defaults: empty)
            #expect(runtime.model.rules.macroEntries.isEmpty && runtime.model.rules.exclusionEntries.isEmpty)
            runtime.type("vn been ")
            #expect(runtime.text == "vn bên ")
        }
    }
}
