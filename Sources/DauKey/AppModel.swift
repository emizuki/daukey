import AppKit
import Observation
import DauKeyEngine
import DauKeyHook

/// What the windows, menu and icon show, and the intents they send to the typing runtime.
///
/// The runtime owns the applied settings; the model shows its snapshots, saves them when they change, and sends one
/// command per user intent. The rule editor and the language are injected; nothing here starts a tap, thread, window
/// or observer.
@MainActor @Observable final class AppModel {
    private(set) var snapshot: Snapshot
    var permissionGranted: Bool
    private(set) var loginEnabled = false
    private(set) var loginRequiresApproval = false
    private(set) var loginError: String?
    var didShowWelcome: Bool {
        didSet { store.saveWelcomeShown(didShowWelcome) }
    }
    let rules: RuleEditorModel
    let localization: LocalizationManager
    let shortcutRecorder: ShortcutRecorder
    let windows: WindowLifecycleManager
    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let commands: AsyncStream<Command>.Continuation
    @ObservationIgnored private var snapshots: AsyncStream<Snapshot>.AsyncIterator
    /// The runtime preferences last saved or loaded.
    @ObservationIgnored private var saved: RuntimePreferences

    init(
        store: PreferencesStore, initial: StartupSettings, permissionGranted: Bool,
        commands: AsyncStream<Command>.Continuation, snapshots: AsyncStream<Snapshot>,
        rules: RuleEditorModel, localization: LocalizationManager
    ) {
        self.store = store
        self.commands = commands
        self.snapshots = snapshots.makeAsyncIterator()
        self.rules = rules
        self.localization = localization
        self.permissionGranted = permissionGranted
        didShowWelcome = initial.didShowWelcome
        saved = initial.runtime
        snapshot = Snapshot(enabled: initial.runtime.enabled, settings: initial.runtime.settings,
                            appMemory: initial.runtime.appMemory, tap: .starting)
        let recorder = ShortcutRecorder(commands: commands)
        shortcutRecorder = recorder
        windows = WindowLifecycleManager(onPanelFocusLost: { recorder.stop() })
    }

    func send(_ command: Command) { commands.yield(command) }

    /// Applies snapshots until the runtime finishes the stream.
    func consumeSnapshots() async {
        while await consumeNextSnapshot() {}
    }

    /// Applies the newest snapshot, waiting for one; false once the stream has finished.
    func consumeNextSnapshot() async -> Bool {
        var iterator = snapshots
        guard let next = await iterator.next(isolation: #isolation) else { return false }
        snapshots = iterator
        snapshot = next
        let runtime = RuntimePreferences(enabled: next.enabled, settings: next.settings, appMemory: next.appMemory)
        if runtime != saved {
            store.saveRuntime(runtime)
            saved = runtime
        }
        shortcutRecorder.update(next.shortcutCapture)
        return true
    }

    func refreshLogin() {
        let status = LoginItem.status
        loginEnabled = status == .enabled
        loginRequiresApproval = status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        let result = LoginItem.setEnabled(enabled)
        loginEnabled = result.status == .enabled
        loginRequiresApproval = result.status == .requiresApproval
        loginError = result.error
    }

    /// Returns typing settings, app memory and the language to their defaults; rules, the welcome flag, login and
    /// permission stay. A recording in progress ends first, before the reset is queued.
    func resetToDefaults() {
        shortcutRecorder.stop()
        send(.resetToDefaults)
        localization.currentLanguage = .vietnamese
    }
}
