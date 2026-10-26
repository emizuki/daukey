import AppKit
import DauKeyEngine
import SwiftUI

@MainActor
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("Chào mừng đến với DauKey")
                    .font(.title2.bold())
                Text("Hai bước nữa là gõ được tiếng Việt.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                HStack {
                    Text("1. Cho phép Trợ năng")
                        .font(.headline)
                    Spacer()
                    if model.permissionGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Đã cho phép Trợ năng")
                    } else {
                        Button("Mở Cài đặt") {
                            Permission.openSettings()
                        }
                        .buttonStyle(.glass)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }

            GroupBox {
                HStack {
                    Text("2. Chọn kiểu gõ")
                        .font(.headline)
                    Spacer()
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
                        Text("Simple Telex").tag(InputMethod.simpleTelex)
                        Text("VNI").tag(InputMethod.vni)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }

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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .containerShape(.rect(cornerRadius: WindowLayout.cornerRadius))
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
