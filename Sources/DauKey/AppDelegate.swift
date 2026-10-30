import AppKit

/// Owns the context-menu controller for the app's lifetime and starts it once the app is ready.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusBarMenuController?
    private var didFinishLaunching = false

    /// Binds the app's model; repeated calls with the same instance do nothing.
    func configure(model: AppModel) {
        if let menuController {
            precondition(menuController.model === model, "AppDelegate is bound to one AppModel")
            return
        }
        let controller = StatusBarMenuController(model: model)
        menuController = controller
        if didFinishLaunching { controller.start() }
    }

    /// Applies the current state and language to the context menu and tooltip.
    func refreshPresentation() {
        menuController?.refreshPresentation()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        menuController?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuController?.stop()
    }
}
