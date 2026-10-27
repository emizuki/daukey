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
        commands.continuation.yield(.appActivated("app.a", inlineCompletionApp: false))
        commands.continuation.yield(.setEnabled(false))
        commands.continuation.yield(.appActivated("app.b", inlineCompletionApp: false))
        commands.continuation.yield(.setEnabled(true))
        commands.continuation.yield(.appActivated("app.a", inlineCompletionApp: false))
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
        let customShortcut = ShortcutConfig(modifiers: [.control], keyCode: 0x06)
        let snapshot = Snapshot(enabled: false,
            options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .off, allowForeignConsonants: true, autoCapitalize: true),
            appMemory: ["app.a": false, "app.b": true], tap: .running,
            perAppSwitching: false, soundEnabled: true, shortcut: customShortcut)
        StoredSettings.save(snapshot, to: defaults)
        let loaded = StoredSettings(defaults)
        #expect(!loaded.enabled)
        #expect(loaded.options == snapshot.options)
        #expect(loaded.appMemory == snapshot.appMemory)
        #expect(!loaded.perAppSwitching)
        #expect(loaded.soundEnabled)
        #expect(loaded.shortcut == customShortcut)
        defaults.set("unknown", forKey: "inputMethod")
        defaults.set("unknown", forKey: "toneStyle")
        defaults.set("unknown", forKey: "spelling")
        let unknown = StoredSettings(defaults)
        #expect(unknown.options.inputMethod == .telex)
        #expect(unknown.options.toneStyle == .old)
        #expect(unknown.options.spelling == .checkAndRestore)
    }
    @Test func inputMethodSettingsRoundTripSimpleTelexAndLegacyValues() {
        let name = "DauKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for (stored, method) in [
            ("telex", InputMethod.telex), ("simpleTelex", InputMethod.simpleTelex), ("vni", InputMethod.vni),
        ] {
            defaults.set(stored, forKey: "inputMethod")
            #expect(StoredSettings(defaults).options.inputMethod == method)
            defaults.removeObject(forKey: "inputMethod")
            let snapshot = Snapshot(enabled: true, options: Options(inputMethod: method), appMemory: [:], tap: .running)
            StoredSettings.save(snapshot, to: defaults)
            #expect(defaults.string(forKey: "inputMethod") == stored)
        }
    }
    @Test @MainActor func resetToDefaultsRestoresInitialState() async {
        let name = "DauKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let customShortcut = ShortcutConfig(modifiers: [.command], keyCode: 0x01)
        let customized = Snapshot(
            enabled: false,
            options: Options(inputMethod: .vni, toneStyle: .modern, spelling: .off, allowForeignConsonants: true, autoCapitalize: true),
            appMemory: ["app.custom": false],
            tap: .running,
            perAppSwitching: false,
            soundEnabled: true,
            shortcut: customShortcut
        )
        StoredSettings.save(customized, to: defaults)

        let model = AppModel(defaults: defaults)
        model.resetToDefaults()
        // Allow task to process reset command
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(model.snapshot.enabled == true)
        #expect(model.snapshot.options == Options())
        #expect(model.snapshot.perAppSwitching == true)
        #expect(model.snapshot.soundEnabled == false)
        #expect(model.snapshot.shortcut == ShortcutConfig())
    }
}
