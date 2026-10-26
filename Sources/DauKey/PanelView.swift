import AppKit
import DauKeyEngine
import DauKeyHook
import SwiftUI

@MainActor
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            mainCard

            VStack(alignment: .leading, spacing: 6) {
                Text("Kiểu gõ")
                Picker("Kiểu gõ", selection: optionBinding(\.inputMethod)) {
                    Text("Telex").tag(InputMethod.telex)
                    Text("VNI").tag(InputMethod.vni)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Đặt dấu")
                Picker("Đặt dấu", selection: optionBinding(\.toneStyle)) {
                    Text("hòa").tag(ToneStyle.old)
                    Text("hoà").tag(ToneStyle.modern)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Picker("Chính tả", selection: optionBinding(\.spelling)) {
                Text("Tắt").tag(Spelling.off)
                Text("Kiểm tra").tag(Spelling.check)
                Text("Kiểm tra và khôi phục").tag(Spelling.checkAndRestore)
            }
            .pickerStyle(.menu)

            Toggle(
                "Phụ âm ngoại (z, f, j, w)",
                isOn: optionBinding(\.allowForeignConsonants)
            )
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "Khởi động cùng máy",
                    isOn: Binding(
                        get: { model.loginEnabled },
                        set: { model.setLoginEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                if let error = model.loginError {
                    Text("Không đổi được: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.loginRequiresApproval {
                    Text("Cần duyệt trong Cài đặt › Mục đăng nhập")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Thoát") {
                    NSApp.terminate(nil)
                }
            }
        }
        .font(.subheadline)
        .controlSize(.small)
        .padding(14)
        .frame(width: 290)
        .background(.regularMaterial)
        .onAppear {
            model.refreshLogin()
        }
    }

    @ViewBuilder
    private var mainCard: some View {
        switch model.snapshot.tap {
        case .noPermission:
            warningCard(
                subtitle: "Cần bật DauKey trong mục Trợ năng",
                showsGuide: true
            )
        case .unavailable:
            warningCard(
                subtitle: "Không bắt được phím. Thử thoát rồi mở lại DauKey.",
                showsGuide: false
            )
        case .starting, .running:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    badge
                    Text("Tiếng Việt")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Toggle(
                        "Tiếng Việt",
                        isOn: Binding(
                            get: { model.snapshot.enabled },
                            set: { model.send(.setEnabled($0)) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Text("⌃⇧ để chuyển · nhớ theo từng app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var badge: some View {
        Text(model.snapshot.enabled ? "V" : "E")
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(model.snapshot.enabled ? Color.white : Color.secondary)
            .frame(width: 34, height: 34)
            .background(
                model.snapshot.enabled ? Color.green : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                if !model.snapshot.enabled {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.secondary, lineWidth: 1.5)
                }
            }
            .accessibilityHidden(true)
    }

    private func warningCard(subtitle: String, showsGuide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Chưa gõ được tiếng Việt", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(subtitle)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if showsGuide {
                Button("Mở hướng dẫn") {
                    openWindow(id: "welcome")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private func optionBinding<Value>(_ keyPath: WritableKeyPath<Options, Value>) -> Binding<Value> {
        Binding(
            get: { model.snapshot.options[keyPath: keyPath] },
            set: { value in
                var options = model.snapshot.options
                options[keyPath: keyPath] = value
                model.send(.setOptions(options))
            }
        )
    }
}
