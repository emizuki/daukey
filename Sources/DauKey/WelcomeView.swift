import AppKit
import DauKeyEngine
import SwiftUI

@MainActor
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                Spacer()
                LiquidGlassSelectPicker(
                    title: l10n.tr(.appLanguage),
                    items: AppLanguage.allCases,
                    selection: Binding(
                        get: { l10n.currentLanguage },
                        set: { l10n.currentLanguage = $0 }
                    ),
                    itemTitle: { "\($0.flag)  \($0.displayName)" }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.tr(.welcomeTitle))
                    .font(.title2.bold())
                Text(l10n.tr(.welcomeSubtitle))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                HStack {
                    Text(l10n.tr(.welcomeStep1))
                        .font(.headline)
                    Spacer()
                    if model.permissionGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.green)
                            Text(l10n.tr(.welcomePermissionGranted))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    } else {
                        Button {
                            Permission.openSettings()
                        } label: {
                            Text(l10n.tr(.welcomeOpenSettings))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)

                HStack {
                    Text(l10n.tr(.welcomeStep2))
                        .font(.headline)
                    Spacer()
                    Picker(
                        l10n.tr(.inputMethod),
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
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)
            }

            HStack {
                Spacer()
                Button(l10n.tr(.welcomeDone)) {
                    model.didShowWelcome = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .ignoresSafeArea()
        .padding(20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .background(GlassBackgroundView().ignoresSafeArea())
        .containerShape(.rect(cornerRadius: WindowLayout.cornerRadius))
        .onAppear {
            WindowLifecycleManager.windowOpened("welcome")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: { $0.title == "DauKey" }) {
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    if let fitting = window.contentView?.fittingSize, fitting.height > 0 {
                        window.setContentSize(fitting)
                    }
                    window.orderFrontRegardless()
                }
            }
        }
        .onDisappear {
            WindowLifecycleManager.windowClosed("welcome")
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
