import AppKit
import SwiftUI

@MainActor struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    private let onPresentationChange: () -> Void
    private static let on = image(enabled: true)
    private static let off = image(enabled: false)
    private static let onSecure = secureImage()
    static func prepareImages() { _ = on; _ = off; _ = onSecure }

    init(onPresentationChange: @escaping () -> Void) {
        self.onPresentationChange = onPresentationChange
    }

    /// The status item tooltip for the given state in the current language.
    static func tooltip(enabled: Bool, localization: LocalizationManager) -> String {
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "DauKey"
        return localization.tr(.menuBarTooltip(appName: appName, enabled: enabled))
    }

    private var iconImage: NSImage {
        if model.isSecureInputEnabled && model.snapshot.enabled {
            return Self.onSecure
        } else {
            return model.snapshot.enabled ? Self.on : Self.off
        }
    }

    var body: some View {
        Image(nsImage: iconImage)
            .help(Self.tooltip(enabled: model.snapshot.enabled, localization: model.localization))
            .onAppear(perform: onPresentationChange)
            .onChange(of: model.snapshot.enabled) { _, _ in
                onPresentationChange()
            }
            .onChange(of: model.isSecureInputEnabled) { _, _ in
                onPresentationChange()
            }
            .onChange(of: model.localization.currentLanguage) { _, _ in
                onPresentationChange()
            }
    }

    private static func image(enabled: Bool) -> NSImage {
        let renderer = ImageRenderer(content: Icon(enabled: enabled))
        renderer.scale = 2
        let image = renderer.nsImage!
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    private static func secureImage() -> NSImage {
        let lightRenderer = ImageRenderer(content: SecureIcon(isDark: false))
        lightRenderer.scale = 2
        let lightImage = lightRenderer.nsImage!

        let darkRenderer = ImageRenderer(content: SecureIcon(isDark: true))
        darkRenderer.scale = 2
        let darkImage = darkRenderer.nsImage!
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let source = isDark ? darkImage : lightImage
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private struct Icon: View {
        let enabled: Bool
        var body: some View {
            Text(enabled ? "V" : "E")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
        }
    }

    private struct SecureIcon: View {
        let isDark: Bool

        var body: some View {
            let fg = isDark ? Color.white : Color.black
            ZStack(alignment: .bottomTrailing) {
                Text("V")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(fg)
                    .frame(width: 16, height: 16)

                Circle()
                    .fill(Color.yellow)
                    .frame(width: 5, height: 5)
                    .overlay(
                        Circle().strokeBorder(isDark ? Color.black : Color.white, lineWidth: 0.7)
                    )
            }
            .frame(width: 16, height: 16)
        }
    }
}
