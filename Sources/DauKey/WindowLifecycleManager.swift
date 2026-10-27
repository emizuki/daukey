import AppKit

@MainActor
enum WindowLifecycleManager {
    private static var activeWindows: Set<String> = []

    static func windowOpened(_ id: String) {
        activeWindows.insert(id)
        updateDockPolicy()
    }

    static func windowClosed(_ id: String) {
        activeWindows.remove(id)
        updateDockPolicy()
    }

    private static func updateDockPolicy() {
        if !activeWindows.isEmpty {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
        } else {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
