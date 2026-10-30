import AppKit
import SwiftUI

/// The panel as hosted inside the glass view, with window opening forwarded from the scene.
@MainActor
struct GlassPanelContent: View {
    let model: AppModel
    let openWindow: OpenWindowAction

    var body: some View {
        PanelView(openSettingsWindow: { id in openWindow(id: id) })
            .environment(model)
    }
}

/// The single glass background of the menu-bar popup; the panel is its content view.
@MainActor
final class DirectGlassHost: NSGlassEffectView {
    let hosting: NSHostingView<GlassPanelContent>

    init(content: GlassPanelContent) {
        hosting = NSHostingView(rootView: content)
        super.init(frame: .zero)
        style = .regular
        // The menu-bar window owns the outer corner shape.
        cornerRadius = 0
        tintColor = nil
        contentView = hosting
        hosting.autoresizingMask = [.width, .height]
        frame.size = hosting.fittingSize
        hosting.frame = bounds
    }

    required init?(coder: NSCoder) { fatalError("Only programmatic construction is supported") }

    override var intrinsicContentSize: NSSize { hosting.fittingSize }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }
}

/// Content of the `MenuBarExtra` window: the panel hosted directly in `NSGlassEffectView`.
@MainActor
struct DirectGlassPanel: NSViewRepresentable {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> DirectGlassHost {
        DirectGlassHost(content: GlassPanelContent(model: model, openWindow: openWindow))
    }

    func updateNSView(_ view: DirectGlassHost, context: Context) {
        view.hosting.rootView = GlassPanelContent(model: model, openWindow: openWindow)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DirectGlassHost, context: Context) -> CGSize? {
        nsView.hosting.fittingSize
    }
}
