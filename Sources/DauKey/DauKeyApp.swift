import SwiftUI
import AppKit

@main struct DauKeyApp: App {
    @State private var model = AppModel()
    init() { MenuBarIcon.prepareImages() }
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 16) {
                HStack {
                    Text(model.snapshot.enabled ? "V" : "E")
                        .font(.title2.bold()).padding(8)
                        .background(model.snapshot.enabled ? Color.accentColor : Color.secondary, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text("Tiếng Việt").font(.headline)
                        Text("⌃⇧ để chuyển · nhớ theo từng app").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Tiếng Việt", isOn: Binding(get: { model.snapshot.enabled },
                        set: { model.send(.setEnabled($0)) })).labelsHidden()
                }
                Button("Thoát") { NSApp.terminate(nil) }
            }.padding().frame(width: 290)
        } label: { MenuBarIcon().environment(model) }
        .menuBarExtraStyle(.window)
    }
}
