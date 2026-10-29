import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: { $0.title == "DauKey" }) {
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }
}

@main struct DauKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    init() {
        MenuBarIcon.prepareImages()
    }
    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(model)
        } label: { MenuBarIcon().environment(model) }
        .menuBarExtraStyle(.window)
        Window("DauKey", id: "welcome") {
            WelcomeView().environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.didShowWelcome && model.permissionGranted ? .suppressed : .presented)

        Window("Thiết lập quy tắc gõ tắt", id: "macros") {
            MacroSettingsView()
        }
        .windowResizability(.contentSize)

        Window("Thiết lập danh sách ngoại lệ", id: "exclusions") {
            ExclusionSettingsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
