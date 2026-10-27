import SwiftUI

@main struct DauKeyApp: App {
    @State private var model = AppModel()
    init() {
        MenuBarIcon.prepareImages()
        if !model.didShowWelcome || !model.permissionGranted {
            WindowLifecycleManager.windowOpened("welcome")
        }
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
