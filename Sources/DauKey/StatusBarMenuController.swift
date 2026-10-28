import AppKit

@MainActor
final class StatusBarMenuController: NSObject, NSMenuDelegate {
    static let shared = StatusBarMenuController()
    private var model: AppModel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var targetButton: NSStatusBarButton?
    let contextMenu = NSMenu(title: "DauKey Menu")

    func setup(model: AppModel) {
        guard NSApp != nil else { return }
        self.model = model
        contextMenu.delegate = self
        buildMenu()
        updateToolTip()

        // Search for button now and with retries as SwiftUI initializes status item
        for delay in [0.05, 0.2, 0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.findAndAttachButton()
            }
        }

        // 1. Local event monitor for rightMouseDown and Control+LeftClick
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                let isRight = event.type == .rightMouseDown
                let isCtrlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
                guard isRight || isCtrlClick else { return event }

                if let window = event.window, window.className.contains("StatusBar") {
                    if let button = self.findStatusBarButton(in: window) {
                        let loc = button.convert(event.locationInWindow, from: nil)
                        if button.bounds.contains(loc) {
                            self.showContextMenu(in: button)
                            return nil
                        }
                    } else if let button = self.targetButton ?? self.findAnyStatusBarButton() {
                        self.showContextMenu(in: button)
                        return nil
                    }
                }
                return event
            }
        }

        // 2. Global event monitor when DauKey is in background
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self else { return }
                guard let button = self.targetButton ?? self.findAnyStatusBarButton(),
                      let window = button.window else { return }
                let mouseLocation = NSEvent.mouseLocation
                if window.frame.contains(mouseLocation) {
                    DispatchQueue.main.async {
                        self.showContextMenu(in: button)
                    }
                }
            }
        }
    }

    func findAndAttachButton() {
        guard NSApp != nil else { return }
        if let button = findAnyStatusBarButton() {
            targetButton = button
            updateToolTip()
        }
    }

    func updateToolTip(_ customText: String? = nil) {
        guard let button = targetButton ?? findAnyStatusBarButton() else { return }
        if let customText {
            button.toolTip = customText
        } else if let model {
            let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
                ?? "DauKey"
            button.toolTip = LocalizationManager.shared.tr(.menuBarTooltip(appName: appName, enabled: model.snapshot.enabled))
        }
    }

    private func findAnyStatusBarButton() -> NSStatusBarButton? {
        for window in NSApplication.shared.windows where window.className.contains("StatusBar") {
            if let button = findStatusBarButton(in: window) {
                return button
            }
        }
        return nil
    }

    private func findStatusBarButton(in window: NSWindow) -> NSStatusBarButton? {
        guard let contentView = window.contentView else { return nil }
        return findButton(in: contentView)
    }

    private func findButton(in view: NSView) -> NSStatusBarButton? {
        if let btn = view as? NSStatusBarButton { return btn }
        for sub in view.subviews {
            if let btn = findButton(in: sub) { return btn }
        }
        return nil
    }

    func showContextMenu(in button: NSStatusBarButton) {
        updateAppearance()
        updateMenuItems()
        NSApp.activate(ignoringOtherApps: true)
        contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func updateAppearance() {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let isDark = (globalDomain?["AppleInterfaceStyle"] as? String) == "Dark"
        contextMenu.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func buildMenu() {
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
    }

    private func updateMenuItems() {
        guard let model else { return }
        if let item = contextMenu.items.first {
            item.state = model.snapshot.enabled ? .on : .off
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateAppearance()
        updateMenuItems()
    }

    @objc private func toggleEnabledAction() {
        guard let model else { return }
        model.send(.setEnabled(!model.snapshot.enabled))
    }

    @objc private func resetAction() {
        guard let model else { return }
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
