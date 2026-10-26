import SwiftUI

@main struct DauKeyApp: App {
    @State private var model = AppModel()
    init() { MenuBarIcon.prepareImages() }
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
    }
}
