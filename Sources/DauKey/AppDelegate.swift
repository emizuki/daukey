import AppKit

/// Holds the app's one runtime and the context-menu controller for the app's lifetime; starts both once the app is
/// ready and stops them when it terminates.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime?
    private var menuController: StatusBarMenuController?
    private var didFinishLaunching = false

    /// Binds the app's runtime; repeated calls with the same instance do nothing.
    func configure(runtime: AppRuntime) {
        if let bound = self.runtime {
            precondition(bound === runtime, "AppDelegate is bound to one AppRuntime")
            return
        }
        self.runtime = runtime
        let controller = StatusBarMenuController(model: runtime.model)
        menuController = controller
        if didFinishLaunching { start() }
    }

    /// Applies the current state and language to the context menu and tooltip.
    func refreshPresentation() {
        menuController?.refreshPresentation()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuController?.stop()
        runtime?.stop()
    }

    private func start() {
        runtime?.start()
        menuController?.start()
    }
}
