import AppKit
import DauKeyEngine
import DauKeyHook
import SwiftUI

enum WindowLayout {
    // Measured outer corner radius of both the panel and welcome windows.
    static let cornerRadius: CGFloat = 24
}

@MainActor
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var isQuitHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            optionsSection
            Divider()
            loginSection
            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Thoát")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background {
                if isQuitHovered {
                    ConcentricRectangle(corners: .concentric(minimum: 6), isUniform: true)
                        .fill(.fill.quaternary)
                }
            }
            .onHover { isQuitHovered = $0 }
            .padding(.horizontal, -8)
        }
        .font(.subheadline)
        .controlSize(.small)
        .padding(14)
        .frame(width: 290)
        .containerShape(.rect(cornerRadius: WindowLayout.cornerRadius))
        .onAppear {
            model.refreshLogin()
        }
        .onDisappear { isQuitHovered = false }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kiểu gõ")
                Spacer()
                Picker("Kiểu gõ", selection: optionBinding(\.inputMethod)) {
                    Text("Telex").tag(InputMethod.telex)
                    Text("VNI").tag(InputMethod.vni)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            HStack {
                Text("Đặt dấu")
                Spacer()
                Picker("Đặt dấu", selection: optionBinding(\.toneStyle)) {
                    Text("hòa").tag(ToneStyle.old)
                    Text("hoà").tag(ToneStyle.modern)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            HStack {
                Text("Chính tả")
                Spacer()
                Picker("Chính tả", selection: optionBinding(\.spelling)) {
                    Text("Tắt").tag(Spelling.off)
                    Text("Kiểm tra").tag(Spelling.check)
                    Text("Kiểm tra và khôi phục").tag(Spelling.checkAndRestore)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            HStack {
                Text("Phụ âm ngoại (z, f, j, w)")
                Spacer()
                Toggle(
                    "Phụ âm ngoại (z, f, j, w)",
                    isOn: optionBinding(\.allowForeignConsonants)
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Khởi động cùng máy")
                Spacer()
                Toggle(
                    "Khởi động cùng máy",
                    isOn: Binding(
                        get: { model.loginEnabled },
                        set: { model.setLoginEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

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
    }

    @ViewBuilder
    private var header: some View {
        switch model.snapshot.tap {
        case .noPermission:
            warningHeader(
                subtitle: "Cần bật DauKey trong mục Trợ năng",
                showsGuide: true
            )
        case .unavailable:
            warningHeader(
                subtitle: "Không bắt được phím. Thử thoát rồi mở lại DauKey.",
                showsGuide: false
            )
        case .starting, .running:
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DauKey")
                        .font(.headline)
                    Text("⌃⇧ để chuyển · nhớ theo từng ứng dụng")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        }
    }

    private func warningHeader(subtitle: String, showsGuide: Bool) -> some View {
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
                .buttonStyle(.glass)
            }
        }
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
