import AppKit
import Carbon
import DauKeyEngine
import DauKeyHook

/// The one runtime of the app: the preferences store, the model every scene shows, and, once started, the typing
/// thread with its Typist, the text-context reader, and the observers that feed app and input-source changes.
///
/// The rule editor is built from the store first and its compiled tables seed the typing core, so saved rules apply
/// from the first key. Nothing runs until `start`.
@MainActor final class AppRuntime {
    let model: AppModel
    private let rules: RuleEditorModel
    private let startup: StartupSettings
    private let commands: AsyncStream<Command>
    private let continuation: AsyncStream<Command>.Continuation
    private let snapshots: AsyncStream<Snapshot>.Continuation
    private var typing: TypingThread?
    private var reader: TextContextReader?
    private var commandTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults = .standard) {
        let store = PreferencesStore(defaults: defaults)
        startup = store.load()
        let commandPair = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshotPair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        commands = commandPair.stream
        continuation = commandPair.continuation
        snapshots = snapshotPair.continuation
        let continuation = commandPair.continuation
        rules = RuleEditorModel(store: store) { continuation.yield(.replaceRules($0)) }
        model = AppModel(
            store: store, initial: startup, permissionGranted: Permission.isGranted,
            commands: continuation, snapshots: snapshotPair.stream, rules: rules,
            localization: LocalizationManager(language: startup.language, store: store)
        )
    }

    /// Starts typing; call once the app has finished launching. Repeated calls do nothing.
    func start() {
        guard typing == nil else { return }
        let typing = TypingThread()
        self.typing = typing
        let continuation = continuation
        let reader = TextContextReader { continuation.yield(.context($0)) }
        self.reader = reader
        reader.start()
        // Rule edits made before now are still queued and replace these same tables in order.
        let typist = Typist(
            executor: typing.executor, enabled: startup.runtime.enabled, settings: startup.runtime.settings,
            appMemory: startup.runtime.appMemory, rules: rules.tables, snapshots: snapshots,
            readContext: { reader.request($0) }
        )
        let commands = commands
        commandTask = Task { await drainCommands(commands, into: typist) }
        let model = model
        snapshotTask = Task { await model.consumeSnapshots() }
        model.send(.start)
        appActivated(NSWorkspace.shared.frontmostApplication)
        observe()
        model.refreshLogin()
    }

    /// Removes the observers and stops reading context; call when the app terminates.
    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        reader?.stop()
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appActivated(app) }
        }))
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.send(.checkTap) }
        }))
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.send(.inputSourceChanged) }
        }))
    }

    private func appActivated(_ app: NSRunningApplication?) {
        let info = app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
        let declarations = info?["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let identifiers = declarations.compactMap { $0["UTTypeIdentifier"] as? String }
        let inlineCompletionApp = InlineCompletionApp.matches(
            bundleID: app?.bundleIdentifier, exportedTypeIdentifiers: identifiers)
        model.send(.appActivated(
            bundleID: app?.bundleIdentifier, processID: app?.processIdentifier,
            inlineCompletionApp: inlineCompletionApp
        ))
    }
}
