import AppKit
import DauKeyEngine
import SwiftUI

@MainActor
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chào mừng đến với DauKey")
                        .font(.title2.bold())
                    Text("Hai bước nữa là gõ được tiếng Việt.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("1. Cho phép Trợ năng")
                            .font(.headline)
                        Spacer()
                        if model.permissionGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Đã cho phép Trợ năng")
                        }
                    }
                    if !model.permissionGranted {
                        Button("Mở Cài đặt") {
                            Permission.openSettings()
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 10)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("2. Chọn kiểu gõ")
                        .font(.headline)
                    Picker(
                        "Chọn kiểu gõ",
                        selection: Binding(
                            get: { model.snapshot.options.inputMethod },
                            set: { inputMethod in
                                var options = model.snapshot.options
                                options.inputMethod = inputMethod
                                model.send(.setOptions(options))
                            }
                        )
                    ) {
                        Text("Telex").tag(InputMethod.telex)
                        Text("VNI").tag(InputMethod.vni)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 10)))

                Text("Bấm biểu tượng V trên thanh menu để đổi các tuỳ chọn khác. Bật/tắt nhanh: ⌃⇧")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Xong") {
                        model.didShowWelcome = true
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 440)
            .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 10)))
        }
        .containerShape(.rect(cornerRadius: GlassLayout.containerCornerRadius))
        .containerBackground(.clear, for: .window)
        .onAppear {
            NSApp.activate()
            // This is the explicit title of the single welcome Window scene.
            NSApp.windows.first { $0.title == "DauKey" }?.orderFrontRegardless()
        }
        .task(id: model.snapshot.tap) { @MainActor in
            await monitorPermission()
        }
    }

    private func monitorPermission() async {
        model.permissionGranted = Permission.isGranted
        if model.permissionGranted {
            model.send(.checkTap)
            return
        }

        while !Task.isCancelled && !model.permissionGranted {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled, !model.permissionGranted else { return }
            model.permissionGranted = Permission.isGranted
            if model.permissionGranted {
                model.send(.checkTap)
            }
        }
    }
}
