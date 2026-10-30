import AppKit
import Carbon
import Observation
import DauKeyEngine
import DauKeyHook

struct StoredSettings {
    var enabled: Bool
    var options: Options
    var appMemory: [String: Bool]
    var perAppSwitching: Bool
    var soundEnabled: Bool
    var shortcut: ShortcutConfig
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
            allowForeignConsonants: defaults.bool(forKey: "allowForeignConsonants"),
            autoCapitalize: defaults.bool(forKey: "autoCapitalize"))
        appMemory = defaults.dictionary(forKey: "appMemory") as? [String: Bool] ?? [:]
        perAppSwitching = defaults.object(forKey: "perAppSwitching") as? Bool ?? true
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        let rawMods = (defaults.object(forKey: "shortcutModifiers") as? NSNumber)?.uint8Value ?? Modifiers([.control, .shift]).rawValue
        let keyCodeInt = (defaults.object(forKey: "shortcutKeyCode") as? NSNumber)?.intValue ?? -1
        let keyCode: UInt16? = keyCodeInt >= 0 ? UInt16(keyCodeInt) : nil
        shortcut = ShortcutConfig(modifiers: Modifiers(rawValue: rawMods), keyCode: keyCode)
    }
    static func save(_ snapshot: Snapshot, to defaults: UserDefaults) {
        let values: [String: Any] = [
            "enabled": snapshot.enabled,
            "inputMethod": snapshot.options.inputMethod.rawValue,
            "toneStyle": snapshot.options.toneStyle == .old ? "old" : "modern",
            "spelling": snapshot.options.spelling == .off ? "off" : snapshot.options.spelling == .check ? "check" : "checkAndRestore",
            "allowForeignConsonants": snapshot.options.allowForeignConsonants,
            "autoCapitalize": snapshot.options.autoCapitalize,
            "appMemory": snapshot.appMemory,
            "perAppSwitching": snapshot.perAppSwitching,
            "soundEnabled": snapshot.soundEnabled,
            "shortcutModifiers": snapshot.shortcut.modifiers.rawValue,
            "shortcutKeyCode": snapshot.shortcut.keyCode.map { Int($0) } ?? -1,
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
    private var permissionTask: Task<Void, Never>?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permissionGranted = Permission.isGranted
        didShowWelcome = defaults.bool(forKey: "didShowWelcome")
        let stored = StoredSettings(defaults)
        var initialOptions = stored.options
        initialOptions.exclusions = ExclusionStore.shared.exclusionSet
        initialOptions.macros = MacroStore.shared.macroMap
        snapshot = Snapshot(enabled: stored.enabled, options: initialOptions,
                            appMemory: stored.appMemory, tap: .starting,
                            perAppSwitching: stored.perAppSwitching,
                            soundEnabled: stored.soundEnabled,
                            shortcut: stored.shortcut)
        let commandPair = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshotPair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        commands = commandPair.continuation
        let typing = TypingThread()
        let typist = Typist(executor: typing.executor, enabled: stored.enabled, options: initialOptions,
                            appMemory: stored.appMemory,
                            perAppSwitching: stored.perAppSwitching,
                            soundEnabled: stored.soundEnabled,
                            shortcut: stored.shortcut,
                            snapshots: snapshotPair.continuation)
        commandTask = Task { await drainCommands(commandPair.stream, into: typist) }
        snapshotTask = Task { [weak self] in
            for await snapshot in snapshotPair.stream {
                guard let self else { return }
                self.snapshot = snapshot
                StoredSettings.save(snapshot, to: defaults)
            }
        }
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                let current = Permission.isGranted
                if current != self.permissionGranted {
                    self.permissionGranted = current
                    self.send(.checkTap)
                } else if current && self.snapshot.tap != .running {
                    self.send(.checkTap)
                }
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
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("daukeySyncData"),
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncMacrosAndExclusions()
                }
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
    func syncMacrosAndExclusions() {
        var options = snapshot.options
        options.exclusions = ExclusionStore.shared.exclusionSet
        options.macros = MacroStore.shared.macroMap
        send(.setOptions(options))
    }
    func resetToDefaults() {
        send(.resetToDefaults)
        defaults.removeObject(forKey: "enabled")
        defaults.removeObject(forKey: "inputMethod")
        defaults.removeObject(forKey: "toneStyle")
        defaults.removeObject(forKey: "spelling")
        defaults.removeObject(forKey: "allowForeignConsonants")
        defaults.removeObject(forKey: "autoCapitalize")
        defaults.removeObject(forKey: "appMemory")
        defaults.removeObject(forKey: "perAppSwitching")
        defaults.removeObject(forKey: "soundEnabled")
        defaults.removeObject(forKey: "shortcutModifiers")
        defaults.removeObject(forKey: "shortcutKeyCode")
        defaults.removeObject(forKey: "appLanguage")
        LocalizationManager.shared.currentLanguage = .vietnamese
    }
}
