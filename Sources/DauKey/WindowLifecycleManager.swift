import AppKit
import SwiftUI

/// Follows the app's real windows, reported by the `WindowAttachment` inside each window's content.
///
/// While a document window (welcome, macros, exclusions) is open, DauKey is a regular app with a Dock icon; when the
/// last one closes it returns to the menu bar only. The panel losing key status, closing, or going away calls
/// `onPanelFocusLost`.
@MainActor final class WindowLifecycleManager {
    enum Role { case panel, welcome, macros, exclusions }

    private struct Entry {
        let role: Role
        let observers: [NSObjectProtocol]
    }

    private let onPanelFocusLost: () -> Void
    private var entries: [ObjectIdentifier: Entry] = [:]
    /// Open document windows.
    private var documents: Set<ObjectIdentifier> = []

    init(onPanelFocusLost: @escaping () -> Void) {
        self.onPanelFocusLost = onPanelFocusLost
    }

    func track(_ window: NSWindow, role: Role) {
        let key = ObjectIdentifier(window)
        guard entries[key] == nil else { return }
        let center = NotificationCenter.default
        var observers = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) {
                [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    if let window { self?.untrack(window) }
                }
            },
        ]
        if role == .panel {
            observers.append(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPanelFocusLost() }
            })
        } else {
            if role == .welcome { configureWelcome(window) }
            documents.insert(key)
            updateDockPolicy()
        }
        entries[key] = Entry(role: role, observers: observers)
    }

    func untrack(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let entry = entries.removeValue(forKey: key) else { return }
        for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
        if entry.role == .panel {
            onPanelFocusLost()
        } else {
            documents.remove(key)
            updateDockPolicy()
        }
    }

    /// The welcome window shows its glass background through a clear window, sized to its content; the window scene
    /// keeps it fitting as the content changes.
    private func configureWelcome(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        if let fitting = window.contentView?.fittingSize, fitting.height > 0 {
            window.setContentSize(fitting)
        }
    }

    private func updateDockPolicy() {
        let app = NSApplication.shared
        if documents.isEmpty {
            if app.activationPolicy() != .accessory { app.setActivationPolicy(.accessory) }
        } else {
            if app.activationPolicy() != .regular { app.setActivationPolicy(.regular) }
            app.activate()
        }
    }
}

/// Reports the window that hosts a view's content to the lifecycle manager, and its removal.
struct WindowAttachment: NSViewRepresentable {
    let role: WindowLifecycleManager.Role
    let manager: WindowLifecycleManager

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView(role: role, manager: manager)
    }

    func updateNSView(_ view: AttachmentView, context: Context) {}

    static func dismantleNSView(_ view: AttachmentView, coordinator: ()) {
        view.detach()
    }

    final class AttachmentView: NSView {
        private let role: WindowLifecycleManager.Role
        private let manager: WindowLifecycleManager
        private weak var attached: NSWindow?

        init(role: WindowLifecycleManager.Role, manager: WindowLifecycleManager) {
            self.role = role
            self.manager = manager
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("Only programmatic construction is supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== attached else { return }
            detach()
            if let window {
                attached = window
                manager.track(window, role: role)
            }
        }

        func detach() {
            guard let attached else { return }
            self.attached = nil
            manager.untrack(attached)
        }
    }
}
