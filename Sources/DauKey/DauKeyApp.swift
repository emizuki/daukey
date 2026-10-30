import SwiftUI

@main struct DauKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    init() {
        MenuBarIcon.prepareImages()
    }
    var body: some Scene {
        // `@State` storage is installed only once `body` runs, so the delegate is bound here.
        let _ = appDelegate.configure(model: model)
        MenuBarExtra {
            DirectGlassPanel(model: model)
        } label: {
            MenuBarIcon(onPresentationChange: { [appDelegate] in appDelegate.refreshPresentation() })
                .environment(model)
        }
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
