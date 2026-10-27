import CoreGraphics
import CoreFoundation
import ApplicationServices
import AppKit
import DauKeyEngine
import DauKeyHook
import os

actor Typist {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    private var core: TypingCore
    private let snapshots: AsyncStream<Snapshot>.Continuation
    private var lastSnapshot: Snapshot?
    private var tap: EventTap?
    private var targetTap: EventTap?
    private var spotlightTargets = SpotlightTargets()
    private var watchdog: CFRunLoopTimer?
    private var userInfo: UnsafeMutableRawPointer?
    private let sender = KeySender()
    private var unicodeBuffer = [UniChar](repeating: 0, count: 16)
    private enum Index: Hashable { case standard, foreignTelex, foreignVNI }
    private var warmed: Set<Index> = []
    private let tapLog = Logger(subsystem: "com.emizuki.daukey", category: "tap")
    private let permissionLog = Logger(subsystem: "com.emizuki.daukey", category: "permission")
    init(executor: RunLoopExecutor, enabled: Bool, options: Options, appMemory: [String: Bool],
         perAppSwitching: Bool = true, soundEnabled: Bool = false, shortcut: ShortcutConfig = ShortcutConfig(),
         snapshots: AsyncStream<Snapshot>.Continuation) {
        self.executor = executor
        core = TypingCore(enabled: enabled, options: options, appMemory: appMemory,
                          perAppSwitching: perAppSwitching, soundEnabled: soundEnabled, shortcut: shortcut)
        self.snapshots = snapshots
    }
    func handle(_ command: Command) {
        switch command {
        case .start:
            if watchdog == nil {
                userInfo = Unmanaged.passRetained(self).toOpaque()
                let timer = makeWatchdog(self)
                watchdog = timer
                CFRunLoopAddTimer(executor.runLoop, timer, .commonModes)
                warm(core.snapshot.options)
            }
            checkTap()
        case .checkTap: checkTap()
        case .setEnabled(let enabled): core.setEnabled(enabled)
        case .setOptions(let options):
            core.setOptions(options)
            warm(options)
        case .setPerAppSwitching(let value): core.setPerAppSwitching(value)
        case .setSoundEnabled(let value): core.setSoundEnabled(value)
        case .setShortcut(let config): core.setShortcut(config)
        case .resetToDefaults:
            core.resetToDefaults()
            warm(core.snapshot.options)
        case .appActivated(let id, let inlineCompletionApp):
            spotlightTargets.appActivated()
            core.appActivated(id, inlineCompletionApp: inlineCompletionApp)
        case .inputSourceChanged: core.inputSourceChanged()
        case .reset: core.reset()
        }
        publishSnapshot()
    }
    func checkTap() {
        guard AXIsProcessTrusted() else {
            if core.snapshot.tap != .noPermission {
                tap?.remove()
                tap = nil
                targetTap?.remove()
                targetTap = nil
                core.keyTarget(isSpotlight: false)
                core.reset()
                core.setTap(.noPermission)
                permissionLog.notice("Accessibility permission is missing")
            }
            publishSnapshot()
            return
        }
        if core.snapshot.tap == .noPermission { permissionLog.notice("Accessibility permission granted") }
        if let tap, !CFMachPortIsValid(tap.port) {
            tap.remove()
            self.tap = nil
            tapLog.notice("Watchdog removed invalid event tap")
        } else if let tap, !tap.enabled {
            tap.enable()
            if tap.enabled {
                core.reset()
                core.setTap(.running)
                tapLog.notice("Watchdog re-enabled event tap")
            } else {
                tap.remove()
                self.tap = nil
                tapLog.notice("Watchdog removed event tap that could not be re-enabled")
            }
        }
        if tap == nil, let userInfo {
            targetTap?.remove()
            targetTap = nil
            core.keyTarget(isSpotlight: false)
            tap = EventTap(runLoop: executor.runLoop, userInfo: userInfo, kind: .typing)
            core.reset()
            if tap == nil {
                core.setTap(.unavailable)
                tapLog.error("Could not create event tap; watchdog will retry")
            } else {
                core.setTap(.running)
                tapLog.notice("Event tap created")
            }
        }
        if tap != nil { checkTargetTap() }
        publishSnapshot()
    }
    private func checkTargetTap() {
        if let targetTap, !CFMachPortIsValid(targetTap.port) {
            targetTap.remove()
            self.targetTap = nil
            core.keyTarget(isSpotlight: false)
            tapLog.notice("Watchdog removed invalid target event tap")
        } else if let targetTap, !targetTap.enabled {
            core.keyTarget(isSpotlight: false)
            targetTap.enable()
            tapLog.notice("Watchdog requested target event tap recovery")
            if !targetTap.enabled {
                targetTap.remove()
                self.targetTap = nil
                tapLog.notice("Watchdog removed target event tap that could not be re-enabled")
            }
        }
        if targetTap == nil, let userInfo {
            targetTap = EventTap(runLoop: executor.runLoop, userInfo: userInfo, kind: .target)
            if targetTap == nil {
                tapLog.notice("Could not create target event tap; watchdog will retry")
            } else {
                tapLog.notice("Target event tap created")
            }
        }
    }
    func handleTarget(type: CGEventType, event: CGEvent) {
        guard let isSpotlight = spotlightTargets.decision(type: type, event: event, lookup: {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }) else { return }
        core.keyTarget(isSpotlight: isSpotlight)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            targetTap?.enable()
            tapLog.notice("Disabled target event tap recovery requested")
            checkTap()
            return
        }
    }
    func handleTap(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> TapDisposition {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap?.enable()
            core.reset()
            tapLog.notice("Disabled event tap recovery requested")
            checkTap()
            return .pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == KeySender.marker { return .pass }
        let disposition: TapDisposition
        switch type {
        case .keyDown:
            let input = KeyInput(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: Modifiers(event.flags), characters: characters(event))
            let wasEnabled = core.snapshot.enabled
            let decision = core.keyDown(input)
            if core.snapshot.enabled != wasEnabled && core.snapshot.soundEnabled {
                NSSound.beep()
            }
            switch decision {
            case .pass: disposition = .pass
            case .swallow(let steps):
                if !sender.post(steps, proxy: proxy) { core.reset() }
                disposition = .swallow
            case .passAfter(let steps):
                if !sender.post(steps, proxy: proxy) { core.reset() }
                disposition = .pass
            }
        case .flagsChanged:
            let wasEnabled = core.snapshot.enabled
            _ = core.flagsChanged(Modifiers(event.flags))
            if core.snapshot.enabled != wasEnabled && core.snapshot.soundEnabled {
                NSSound.beep()
            }
            disposition = .pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            core.mouseDown()
            disposition = .pass
        default: disposition = .pass
        }
        publishSnapshot()
        return disposition
    }
    private func characters(_ event: CGEvent) -> String {
        var count = 0
        event.keyboardGetUnicodeString(maxStringLength: unicodeBuffer.count,
            actualStringLength: &count, unicodeString: &unicodeBuffer)
        return String(decoding: unicodeBuffer.prefix(count), as: UTF16.self)
    }
    private func warm(_ options: Options) {
        let index: Index
        if options.allowForeignConsonants {
            switch options.inputMethod {
            case .telex, .simpleTelex: index = .foreignTelex
            case .vni: index = .foreignVNI
            }
        } else {
            index = .standard
        }
        guard warmed.insert(index).inserted else { return }
        Task.detached(priority: .utility) {
            var engine = Engine(options: options)
            _ = engine.handle(.char("a"))
            _ = engine.handle(.reset)
        }
    }
    func publishSnapshot() {
        let snapshot = core.snapshot
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        snapshots.yield(snapshot)
    }
}
private func makeWatchdog(_ typist: Typist) -> CFRunLoopTimer {
    CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 2, 2, 0, 0) { _ in
        typist.assumeIsolated { $0.checkTap() }
    }
}
