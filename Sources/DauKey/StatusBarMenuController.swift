import AppKit
import os

/// Shows the context menu on right-click or Control-click of the menu-bar icon.
///
/// `MenuBarExtra` owns the status item, its button and the popup; this controller only
/// observes clicks on that button through a local monitor and never changes the
/// button's target, action or pressed state. A normal left-click passes through.
@MainActor
final class StatusBarMenuController: NSObject, NSMenuDelegate {
    let model: AppModel
    private let logger = Logger(subsystem: "com.emizuki.daukey", category: "menu")
    private var isStarted = false
    private var contextMenu: NSMenu?
    private var mouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private let buttons = NSHashTable<NSStatusBarButton>.weakObjects()

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// Call once the app has finished launching; repeated calls do nothing.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        let menu = NSMenu(title: "DauKey Menu")
        menu.delegate = self
        contextMenu = menu
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, let button = self.contextMenuButton(for: event) else { return event }
            self.showContextMenu(in: button)
            return nil
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAttach() }
        }
        scheduleAttach()
    }

    /// Removes the monitor and observer installed by `start`; repeated calls do nothing.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        contextMenu?.cancelTracking()
        contextMenu = nil
        buttons.removeAllObjects()
    }

    /// Applies the current state and language to the tooltip and menu titles.
    func refreshPresentation() {
        guard isStarted else { return }
        let tooltip = MenuBarIcon.tooltip(enabled: model.snapshot.enabled)
        for button in buttons.allObjects {
            button.toolTip = tooltip
        }
        buildMenu()
    }

    /// The status item's button is installed by `MenuBarExtra` during launch, so it is
    /// looked up on the next main-queue turn rather than synchronously.
    private func scheduleAttach() {
        DispatchQueue.main.async { [weak self] in
            self?.attach()
        }
    }

    private func attach() {
        guard isStarted else { return }
        buttons.removeAllObjects()
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            collectStatusBarButtons(in: contentView)
        }
        if buttons.count == 0 {
            logger.fault("No status bar button found; the context menu is unavailable")
        }
        refreshPresentation()
    }

    private func collectStatusBarButtons(in view: NSView) {
        if let button = view as? NSStatusBarButton {
            buttons.add(button)
            return
        }
        for subview in view.subviews {
            collectStatusBarButtons(in: subview)
        }
    }

    /// The attached button under a right-click or Control-click, if any.
    private func contextMenuButton(for event: NSEvent) -> NSStatusBarButton? {
        let isRightClick = event.type == .rightMouseDown
        let isControlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        guard isRightClick || isControlClick, let window = event.window else { return nil }
        return buttons.allObjects.first { button in
            button.window === window
                && button.bounds.contains(button.convert(event.locationInWindow, from: nil))
        }
    }

    private func showContextMenu(in button: NSStatusBarButton) {
        guard let contextMenu else { return }
        updateAppearance()
        updateMenuItems()
        contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func updateAppearance() {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let isDark = (globalDomain?["AppleInterfaceStyle"] as? String) == "Dark"
        contextMenu?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func buildMenu() {
        guard let contextMenu else { return }
        contextMenu.removeAllItems()

        let toggleItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.contextMenuVietnamese),
            action: #selector(toggleEnabledAction),
            keyEquivalent: ""
        )
        toggleItem.target = self
        contextMenu.addItem(toggleItem)

        contextMenu.addItem(NSMenuItem.separator())

        let feedbackItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.feedbackAndSupport),
            action: #selector(openFeedbackAction),
            keyEquivalent: ""
        )
        feedbackItem.target = self
        contextMenu.addItem(feedbackItem)

        let resetItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.contextMenuReset),
            action: #selector(resetAction),
            keyEquivalent: ""
        )
        resetItem.target = self
        contextMenu.addItem(resetItem)
        contextMenu.addItem(NSMenuItem.separator())

        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "DauKey"
        let quitItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.contextMenuQuit(appName)),
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        contextMenu.addItem(quitItem)
        updateMenuItems()
    }

    private func updateMenuItems() {
        contextMenu?.items.first?.state = model.snapshot.enabled ? .on : .off
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateAppearance()
        updateMenuItems()
    }

    @objc private func toggleEnabledAction() {
        model.send(.setEnabled(!model.snapshot.enabled))
    }

    @objc private func resetAction() {
        model.resetToDefaults()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func openFeedbackAction() {
        if let url = URL(string: "https://github.com/emizuki/daukey") {
            NSWorkspace.shared.open(url)
        }
    }
}
