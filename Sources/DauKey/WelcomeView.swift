import AppKit
import DauKeyEngine
import SwiftUI

@MainActor
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .accessibilityHidden(true)
                    Text(l10n.tr(.welcomeTitle))
                        .font(.title2.bold())
                    Text(l10n.tr(.welcomeSubtitle))
                        .foregroundStyle(.secondary)
                }
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

            GroupBox {
                HStack {
                    Text(l10n.tr(.welcomeStep1))
                        .font(.headline)
                    Spacer()
                    if model.permissionGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel(l10n.tr(.welcomePermissionGranted))
                    } else {
                        Button(l10n.tr(.welcomeOpenSettings)) {
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
                .padding(10)
            }

            Text(l10n.tr(.welcomeNote))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(24)
        .frame(width: 500)
        .containerShape(.rect(cornerRadius: WindowLayout.cornerRadius))
        .onAppear {
            WindowLifecycleManager.windowOpened("welcome")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "DauKey" }?.orderFrontRegardless()
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
