import AppKit
import Carbon
import Observation
import DauKeyEngine
import DauKeyHook

struct StoredSettings {
    var enabled: Bool
    var options: Options
    var appMemory: [String: Bool]
    init(_ defaults: UserDefaults) {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        options = Options(
            inputMethod: defaults.string(forKey: "inputMethod").flatMap(InputMethod.init(rawValue:)) ?? .telex,
            toneStyle: defaults.string(forKey: "toneStyle") == "modern" ? .modern : .old,
            spelling: { switch defaults.string(forKey: "spelling") {
                case "off": return .off
                case "check": return .check
                default: return .checkAndRestore
            } }(),
            allowForeignConsonants: defaults.bool(forKey: "allowForeignConsonants"))
        appMemory = defaults.dictionary(forKey: "appMemory") as? [String: Bool] ?? [:]
    }
    static func save(_ snapshot: Snapshot, to defaults: UserDefaults) {
        let values: [String: Any] = [
            "enabled": snapshot.enabled,
            "inputMethod": snapshot.options.inputMethod.rawValue,
            "toneStyle": snapshot.options.toneStyle == .old ? "old" : "modern",
            "spelling": snapshot.options.spelling == .off ? "off" : snapshot.options.spelling == .check ? "check" : "checkAndRestore",
            "allowForeignConsonants": snapshot.options.allowForeignConsonants,
            "appMemory": snapshot.appMemory,
        ]
        for (key, value) in values {
            if (defaults.object(forKey: key) as? NSObject) != (value as? NSObject) {
                defaults.set(value, forKey: key)
            }
        }
    }
}

@MainActor @Observable final class AppModel {
    private(set) var snapshot: Snapshot
    var permissionGranted: Bool
    private(set) var loginEnabled = false
    private(set) var loginRequiresApproval = false
    private(set) var loginError: String?
    var didShowWelcome: Bool {
        didSet { defaults.set(didShowWelcome, forKey: "didShowWelcome") }
    }
    private let commands: AsyncStream<Command>.Continuation
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var commandTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permissionGranted = Permission.isGranted
        didShowWelcome = defaults.bool(forKey: "didShowWelcome")
        let stored = StoredSettings(defaults)
        snapshot = Snapshot(enabled: stored.enabled, options: stored.options,
                            appMemory: stored.appMemory, tap: .starting)
        let commandPair = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshotPair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        commands = commandPair.continuation
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: stored.enabled, options: stored.options,
                            appMemory: stored.appMemory, snapshots: snapshotPair.continuation)
        commandTask = Task { await drainCommands(commandPair.stream, into: typist) }
        snapshotTask = Task { [weak self] in
            for await snapshot in snapshotPair.stream {
                guard let self else { return }
                self.snapshot = snapshot
                StoredSettings.save(snapshot, to: defaults)
            }
        }
        send(.start)
        appActivated(NSWorkspace.shared.frontmostApplication)
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appActivated(app) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.checkTap) }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.send(.inputSourceChanged) }
            })
        refreshLogin()
    }
    private func appActivated(_ app: NSRunningApplication?) {
        let info = app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
        let declarations = info?["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let identifiers = declarations.compactMap { $0["UTTypeIdentifier"] as? String }
        let inlineCompletionApp = InlineCompletionApp.matches(
            bundleID: app?.bundleIdentifier, exportedTypeIdentifiers: identifiers)
        send(.appActivated(app?.bundleIdentifier, inlineCompletionApp: inlineCompletionApp))
    }
    func send(_ command: Command) { commands.yield(command) }
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
}
