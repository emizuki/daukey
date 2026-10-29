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
        guard let app = NSApp else {
            DispatchQueue.main.async {
                updateDockPolicy()
            }
            return
        }
        if !activeWindows.isEmpty {
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
            app.activate(ignoringOtherApps: true)
        } else {
            if app.activationPolicy() != .accessory {
                app.setActivationPolicy(.accessory)
            }
        }
    }
}
