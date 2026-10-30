import AppKit
import SwiftUI

@MainActor struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    private let onPresentationChange: () -> Void
    private static let on = image(enabled: true)
    private static let off = image(enabled: false)
    static func prepareImages() { _ = on; _ = off }

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

    var body: some View {
        Image(nsImage: model.snapshot.enabled ? Self.on : Self.off)
            .help(Self.tooltip(enabled: model.snapshot.enabled, localization: model.localization))
            .onAppear(perform: onPresentationChange)
            .onChange(of: model.snapshot.enabled) { _, _ in
                onPresentationChange()
            }
            .onChange(of: model.localization.currentLanguage) { _, _ in
                onPresentationChange()
            }
    }

    private static func image(enabled: Bool) -> NSImage {
        let renderer = ImageRenderer(content: Badge(enabled: enabled))
        renderer.scale = 2
        let image = renderer.nsImage!
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    private struct Badge: View {
        let enabled: Bool
        var body: some View {
            ZStack {
                if enabled {
                    RoundedRectangle(cornerRadius: 3).fill(.black)
                    Text("V").font(.system(size: 12, weight: .bold)).blendMode(.destinationOut)
                } else {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.black, lineWidth: 1.2)
                    Text("E").font(.system(size: 12, weight: .bold))
                }
            }.frame(width: 16, height: 16).compositingGroup()
        }
    }
}
