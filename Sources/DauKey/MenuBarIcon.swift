import AppKit
import SwiftUI

@MainActor struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    private let onPresentationChange: () -> Void
    private static let on = image(.on)
    private static let off = image(.off)
    private static let secureInput = image(.secureInput)
    static func prepareImages() { _ = on; _ = off; _ = secureInput }

    init(onPresentationChange: @escaping () -> Void) {
        self.onPresentationChange = onPresentationChange
    }

    /// The status item tooltip for the given state in the current language.
    static func tooltip(enabled: Bool, blockedBySecureInput: Bool, localization: LocalizationManager) -> String {
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "DauKey"
        let state = localization.tr(.menuBarTooltip(appName: appName, enabled: enabled))
        guard blockedBySecureInput else { return state }
        return "\(state)\n\(localization.tr(.secureInputEnabled))"
    }

    private var currentImage: NSImage {
        if model.isBlockedBySecureInput { return Self.secureInput }
        return model.snapshot.enabled ? Self.on : Self.off
    }

    var body: some View {
        Image(nsImage: currentImage)
            .help(Self.tooltip(
                enabled: model.snapshot.enabled,
                blockedBySecureInput: model.isBlockedBySecureInput,
                localization: model.localization
            ))
            .onAppear(perform: onPresentationChange)
            .onChange(of: model.snapshot.enabled) { _, _ in
                onPresentationChange()
            }
            .onChange(of: model.isBlockedBySecureInput) { _, _ in
                onPresentationChange()
            }
            .onChange(of: model.localization.currentLanguage) { _, _ in
                onPresentationChange()
            }
    }

    private enum Appearance { case on, off, secureInput }

    private static func image(_ appearance: Appearance) -> NSImage {
        let renderer = ImageRenderer(content: Badge(appearance: appearance))
        renderer.scale = 2
        let image = renderer.nsImage!
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    private struct Badge: View {
        let appearance: Appearance
        var body: some View {
            ZStack {
                switch appearance {
                case .on:
                    RoundedRectangle(cornerRadius: 3).fill(.black)
                    Text("V").font(.system(size: 12, weight: .bold)).blendMode(.destinationOut)
                case .off:
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.black, lineWidth: 1.2)
                    Text("E").font(.system(size: 12, weight: .bold))
                case .secureInput:
                    // No badge: a filled square would look like the on state.
                    Image(systemName: "exclamationmark.lock.fill").font(.system(size: 15)).foregroundStyle(.black)
                }
            }.frame(width: 16, height: 16).compositingGroup()
        }
    }
}
