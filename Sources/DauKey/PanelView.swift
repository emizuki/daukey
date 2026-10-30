import AppKit
import DauKeyEngine
import DauKeyHook
import Observation
import SwiftUI

enum WindowLayout {
    // Measured outer corner radius of both the panel and welcome windows.
    static let cornerRadius: CGFloat = 24
}

enum ZincPalette {
    static let zinc50 = Color(red: 0.98, green: 0.98, blue: 0.98)
    static let zinc100 = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let zinc200 = Color(red: 0.898, green: 0.906, blue: 0.922)
    static let zinc300 = Color(red: 0.824, green: 0.835, blue: 0.855)
    static let zinc400 = Color(red: 0.631, green: 0.647, blue: 0.686)
    static let zinc500 = Color(red: 0.443, green: 0.455, blue: 0.498)
    static let zinc600 = Color(red: 0.322, green: 0.337, blue: 0.369)
    static let zinc700 = Color(red: 0.247, green: 0.259, blue: 0.286)
    static let zinc800 = Color(red: 0.153, green: 0.165, blue: 0.188)
    static let zinc900 = Color(red: 0.094, green: 0.106, blue: 0.125)
    static let zinc950 = Color(red: 0.035, green: 0.039, blue: 0.047)
}

// MARK: - Reusable Liquid Glass Components

struct GlassBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glassView = glassClass.init()
            return GlassWrapperView(wrapped: glassView)
        }
        let fallback = NSVisualEffectView()
        fallback.material = .popover
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        return GlassWrapperView(wrapped: fallback)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let wrapper = nsView as? GlassWrapperView {
            wrapper.configureWindow()
        }
    }
}

final class GlassWrapperView: NSView {
    let wrapped: NSView

    init(wrapped: NSView) {
        self.wrapped = wrapped
        super.init(frame: .zero)
        addSubview(wrapped)
        wrapped.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        wrapped.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        configureWindow()
    }

    func configureWindow() {
        guard let window = self.window else { return }
        if window.isOpaque {
            window.isOpaque = false
        }
        if window.backgroundColor != .clear {
            window.backgroundColor = .clear
        }
    }
}


private struct SettingRow<Trailing: View>: View {
    let icon: String?
    let flag: String?
    let title: String
    let tooltip: String?
    let trailing: Trailing

    init(
        icon: String? = nil,
        flag: String? = nil,
        title: String,
        tooltip: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.flag = flag
        self.title = title
        self.tooltip = tooltip
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .center) {
                if let flag {
                    Text(flag)
                        .font(.system(size: 15))
                } else if let icon {
                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 20, height: 20, alignment: .center)

            HStack(spacing: 5) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.primary)

                if let tooltip, !tooltip.isEmpty {
                    InstantTooltipButton(tooltip: tooltip)
                }
            }

            Spacer(minLength: 8)

            trailing
                .controlSize(.small)
        }
        .frame(minHeight: 23)
        .padding(.horizontal, 4)
    }
}

private struct InstantTooltipButton: View {
    let tooltip: String
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.65))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(isPresented: $isHovered, arrowEdge: .bottom) {
                Text(tooltip)
                    .font(.caption)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

private struct ActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .center) {
                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isHovered ? Color.white : Color.secondary)
                        .accessibilityHidden(true)
                }
                .frame(width: 20, height: 20, alignment: .center)
                Text(title)
                    .font(.body)
                    .foregroundStyle(isHovered ? Color.white : Color.primary)

                Spacer()
            }
            .frame(minHeight: 23)
            .padding(.horizontal, 4)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct FullWidthSegmentedPicker: NSViewRepresentable {
    @Binding var selection: InputMethod

    private let methods: [InputMethod] = [.telex, .simpleTelex, .vni]
    private let titles: [String] = ["Telex", "Simple Telex", "VNI"]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: titles,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.selectedSegment = methods.firstIndex(of: selection) ?? 0
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        let targetIndex = methods.firstIndex(of: selection) ?? 0
        if control.selectedSegment != targetIndex {
            control.selectedSegment = targetIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: FullWidthSegmentedPicker
        init(_ parent: FullWidthSegmentedPicker) { self.parent = parent }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            if index >= 0 && index < parent.methods.count {
                parent.selection = parent.methods[index]
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            }
        }
    }
}


private struct LiquidGlassIconButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 28, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? (colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.85)) : (colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.50)))
                        .shadow(color: Color.black.opacity(isHovered ? 0.2 : 0.05), radius: isHovered ? 3 : 1, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.35 : 0.8),
                                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct LiquidGlassSelectPicker<Item: Hashable & Identifiable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    let itemTitle: (Item) -> String
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            triggerHaptic()
            showMenu()
        } label: {
            HStack(spacing: 8) {
                Text(itemTitle(selection))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.primary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                    )
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isHovered
                            ? (colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.14))
                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .shadow(
                        color: Color.black.opacity(isHovered ? 0.22 : 0.0),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LiquidGlass.specularGradient(isDark: colorScheme == .dark, isHovered: isHovered),
                        lineWidth: 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let isDark = (colorScheme == .dark) || (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
        menu.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        for item in items {
            let menuItem = NSMenuItem(
                title: itemTitle(item),
                action: #selector(MenuCallback.itemSelected(_:)),
                keyEquivalent: ""
            )
            let callback = MenuCallback {
                selection = item
                triggerHaptic()
            }
            menuItem.target = callback
            menuItem.representedObject = callback
            if selection == item {
                menuItem.state = .on
            }
            menu.addItem(menuItem)
        }

        if let event = NSApp.currentEvent, let window = event.window {
            NSMenu.popUpContextMenu(menu, with: event, for: window.contentView ?? NSView())
        }
    }

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}

private final class MenuCallback: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
    }
    @objc func itemSelected(_ sender: NSMenuItem) {
        action()
    }
}

// MARK: - PanelView

@MainActor
struct PanelView: View {
    @Environment(AppModel.self) private var model
    private let openSettingsWindow: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var l10n: LocalizationManager { model.localization }
    private var recorder: ShortcutRecorder { model.shortcutRecorder }

    @State private var isResetHovered = false
    @State private var isQuitHovered = false
    @State private var isShortcutHovered = false
    @State private var showingResetConfirmation = false

    init(openSettingsWindow: @escaping (String) -> Void) {
        self.openSettingsWindow = openSettingsWindow
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var hasAccessibilityPermission: Bool {
        model.permissionGranted && model.snapshot.tap != .noPermission
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasAccessibilityPermission {
                fullMenuView
            } else {
                permissionNoticeView
            }
        }
        .padding(10)
        .frame(width: 330)
        .confirmationDialog(
            l10n.tr(.resetConfirmTitle),
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(l10n.tr(.resetConfirmAction), role: .destructive) {
                model.resetToDefaults()
                triggerHaptic()
            }
            Button(l10n.tr(.cancel), role: .cancel) {}
        } message: {
            Text(l10n.tr(.resetConfirmMessage))
        }
        .background(WindowAttachment(role: .panel, manager: model.windows))
        .onAppear {
            model.permissionGranted = Permission.isGranted
            model.refreshLogin()
            model.send(.checkTap)
        }
        .onDisappear {
            recorder.stop()
            isResetHovered = false
            isQuitHovered = false
            isShortcutHovered = false
        }
    }

    // MARK: - Notice View When Permission Missing

    private var permissionNoticeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DauKey")
                        .font(.headline.weight(.semibold))
                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }

            Button {
                Permission.openSettings()
                triggerHaptic()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text(l10n.tr(.permissionRequiredTitle))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    }

                    Text(l10n.tr(.permissionRequiredDesc))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()
                        Label(l10n.tr(.openSystemSettings), systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Text(l10n.tr(.permissionTip))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    model.send(.checkTap)
                    triggerHaptic()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                        Text(l10n.tr(.checkAgain))
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.caption.weight(.semibold))
                        Text(l10n.tr(.terminate))
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Full Menu View

    private var fullMenuView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerSection
            inputMethodAndControlSection
            Divider()
            behaviorSection
            Divider()
            systemSection
            footerSection
        }
    }

    // MARK: - 1. Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("DauKey")
                    .font(.headline.weight(.semibold))
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 8)

            Toggle(
                "DauKey Toggle",
                isOn: Binding(
                    get: { model.snapshot.enabled },
                    set: {
                        model.send(.settings(.enabled($0)))
                        triggerHaptic()
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - 2. Input Method & Controls Section

    private var inputMethodAndControlSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            FullWidthSegmentedPicker(selection: Binding(
                get: { model.snapshot.settings.options.inputMethod },
                set: {
                    model.send(.settings(.inputMethod($0)))
                    triggerHaptic()
                }
            ))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 3)

            SettingRow(
                icon: "keyboard",
                title: l10n.tr(.toggleShortcut)
            ) {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        triggerHaptic()
                        recorder.start { newConfig in
                            model.send(.settings(.shortcut(newConfig)))
                            triggerHaptic()
                        }
                    }
                } label: {
                    Text(recorder.isRecording
                         ? l10n.tr(.pressShortcutPlaceholder)
                         : ShortcutLabel.string(for: model.snapshot.settings.shortcut, language: l10n.currentLanguage))
                        .font(.caption.monospaced())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            recorder.isRecording
                                ? Color.accentColor.opacity(0.12)
                                : (isShortcutHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05))
                        )
                        .foregroundStyle(recorder.isRecording ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    recorder.isRecording
                                        ? LinearGradient(colors: [Color.accentColor, Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LiquidGlass.specularGradient(isDark: colorScheme == .dark, isHovered: isShortcutHovered),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .onHover { isShortcutHovered = $0 }
            }

            SettingRow(
                icon: "speaker.wave.2",
                title: l10n.tr(.soundFeedback)
            ) {
                Toggle(l10n.tr(.soundFeedback), isOn: Binding(
                    get: { model.snapshot.settings.soundEnabled },
                    set: {
                        model.send(.settings(.soundEnabled($0)))
                        triggerHaptic()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingRow(
                icon: "macwindow",
                title: l10n.tr(.perAppMemory)
            ) {
                Toggle(l10n.tr(.perAppMemory), isOn: Binding(
                    get: { model.snapshot.settings.perAppSwitching },
                    set: {
                        model.send(.settings(.perAppSwitching($0)))
                        triggerHaptic()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            ActionRow(
                icon: "text.badge.plus",
                title: l10n.tr(.shorthand)
            ) {
                openSettingsWindow("macros")
                NSApp.activate(ignoringOtherApps: true)
                triggerHaptic()
            }

            ActionRow(
                icon: "shield.slash",
                title: l10n.tr(.exclusions)
            ) {
                openSettingsWindow("exclusions")
                NSApp.activate(ignoringOtherApps: true)
                triggerHaptic()
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 3. Behavior Section

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            SettingRow(
                icon: "character.phonetic",
                title: l10n.tr(.toneStyleModern),
                tooltip: l10n.tr(.toneStyleTooltip)
            ) {
                Toggle(l10n.tr(.toneStyleModern), isOn: modernToneBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingRow(
                icon: "character.textbox",
                title: l10n.tr(.foreignConsonants),
                tooltip: l10n.tr(.foreignConsonantsTooltip)
            ) {
                Toggle(l10n.tr(.foreignConsonants), isOn: settingBinding(
                    { $0.options.allowForeignConsonants }, SettingsChange.allowForeignConsonants
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingRow(
                icon: "textformat.size",
                title: l10n.tr(.autoCapitalize)
            ) {
                Toggle(l10n.tr(.autoCapitalize), isOn: settingBinding(
                    { $0.session.autoCapitalize }, SettingsChange.autoCapitalize
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingRow(
                icon: "checkmark.shield",
                title: l10n.tr(.spellCheck),
                tooltip: l10n.tr(.spellCheckTooltip)
            ) {
                Toggle(l10n.tr(.spellCheck), isOn: spellingEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingRow(
                icon: "arrow.uturn.backward",
                title: l10n.tr(.autoRestore),
                tooltip: l10n.tr(.autoRestoreTooltip)
            ) {
                Toggle(l10n.tr(.autoRestore), isOn: autoRestoreBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.snapshot.settings.options.spelling == .off)
            }
            .opacity(model.snapshot.settings.options.spelling == .off ? 0.45 : 1.0)
        }
        .padding(.horizontal, 4)
    }
    // MARK: - 4. System Section

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            SettingRow(
                icon: "globe",
                title: l10n.tr(.appLanguage)
            ) {
                LiquidGlassSelectPicker(
                    title: l10n.tr(.appLanguage),
                    items: AppLanguage.allCases,
                    selection: Binding(
                        get: { l10n.currentLanguage },
                        set: {
                            l10n.currentLanguage = $0
                            triggerHaptic()
                        }
                    ),
                    itemTitle: { "\($0.flag)  \($0.displayName)" }
                )
            }

            SettingRow(
                icon: "power",
                title: l10n.tr(.launchAtLogin)
            ) {
                Toggle(
                    l10n.tr(.launchAtLogin),
                    isOn: Binding(
                        get: { model.loginEnabled },
                        set: {
                            model.setLoginEnabled($0)
                            triggerHaptic()
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            ActionRow(
                icon: "bubble.left.and.bubble.right",
                title: l10n.tr(.feedbackAndSupport)
            ) {
                if let url = URL(string: "https://github.com/emizuki/daukey") {
                    NSWorkspace.shared.open(url)
                    triggerHaptic()
                }
            }

            if let error = model.loginError {
                Text("Không đổi được: \(error)")
                    .font(.caption2)
                    .foregroundStyle(Color.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.loginRequiresApproval {
                Text(l10n.tr(.loginRequiresApproval))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 5. Footer Section

    private var footerSection: some View {
        HStack(spacing: 10) {
            Button {
                showingResetConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 15, weight: .semibold))
                    Text(l10n.tr(.reset))
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isResetHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            LiquidGlass.specularGradient(isDark: colorScheme == .dark, isHovered: isResetHovered),
                            lineWidth: 0.75
                        )
                )
                .foregroundStyle(Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(l10n.tr(.resetHelp))
            .onHover { isResetHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isResetHovered)

            Button {
                triggerHaptic()
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 15, weight: .semibold))
                    Text(l10n.tr(.terminate))
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isQuitHovered ? Color.red.opacity(0.14) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isQuitHovered
                                ? LinearGradient(colors: [Color.red.opacity(0.6), Color.red.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LiquidGlass.specularGradient(isDark: colorScheme == .dark, isHovered: false),
                            lineWidth: 0.75
                        )
                )
                .foregroundStyle(isQuitHovered ? Color.red : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(l10n.tr(.terminateHelp))
            .onHover { isQuitHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isQuitHovered)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    private var modernToneBinding: Binding<Bool> {
        Binding(
            get: { model.snapshot.settings.options.toneStyle == .modern },
            set: { isModern in
                model.send(.settings(.toneStyle(isModern ? .modern : .old)))
                triggerHaptic()
            }
        )
    }

    private var spellingEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.snapshot.settings.options.spelling != .off },
            set: { enabled in
                model.send(.settings(.spelling(enabled ? .checkAndRestore : .off)))
                triggerHaptic()
            }
        )
    }

    private var autoRestoreBinding: Binding<Bool> {
        Binding(
            get: { model.snapshot.settings.options.spelling == .checkAndRestore },
            set: { restore in
                guard model.snapshot.settings.options.spelling != .off else { return }
                model.send(.settings(.spelling(restore ? .checkAndRestore : .check)))
                triggerHaptic()
            }
        )
    }

    /// Shows one setting from the runtime's snapshot and sends only that setting when it changes.
    private func settingBinding<Value>(
        _ value: @escaping (TypingSettings) -> Value, _ change: @escaping (Value) -> SettingsChange
    ) -> Binding<Value> {
        Binding(
            get: { value(model.snapshot.settings) },
            set: {
                model.send(.settings(change($0)))
                triggerHaptic()
            }
        )
    }
}
