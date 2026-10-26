import SwiftUI
import AppKit

@MainActor struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    private static let on = image(enabled: true)
    private static let off = image(enabled: false)
    static func prepareImages() { _ = on; _ = off }
    var body: some View { Image(nsImage: model.snapshot.enabled ? Self.on : Self.off) }
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
