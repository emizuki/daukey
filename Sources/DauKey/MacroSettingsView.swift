import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MacroSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<MacroEntry.ID>()
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) private var colorScheme

    private var rules: RuleEditorModel { model.rules }
    private var l10n: LocalizationManager { model.localization }

    var body: some View {
        VStack(spacing: 0) {
            Table(of: MacroEntry.self, selection: $selection) {
                TableColumn(l10n.tr(.triggerColumn)) { entry in
                    TextField(l10n.tr(.triggerPlaceholder), text: Binding(
                        get: { binding(for: entry).wrappedValue.trigger },
                        set: { binding(for: entry).wrappedValue.trigger = $0.filter { !$0.isWhitespace } }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                }
                .width(min: 130, ideal: 160)

                TableColumn(l10n.tr(.replacementColumn)) { entry in
                    TextField(l10n.tr(.replacementPlaceholder), text: binding(for: entry).replacement)
                        .textFieldStyle(.plain)
                }
                .width(min: 220, ideal: 300)
            } rows: {
                ForEach(rules.macroEntries) { entry in
                    TableRow(entry)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 8) {
                ToolbarIconButton(icon: "plus", helpText: l10n.tr(.addRuleHelp)) {
                    let newId = rules.addMacro()
                    selection = [newId]
                }

                ToolbarIconButton(icon: "minus", helpText: l10n.tr(.deleteRulesHelp), isDisabled: selection.isEmpty) {
                    rules.removeMacros(selection)
                    selection.removeAll()
                }

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)

                ToolbarIconButton(icon: "square.and.arrow.down", helpText: l10n.tr(.importRules)) {
                    importCSV()
                }

                ToolbarIconButton(icon: "square.and.arrow.up", helpText: l10n.tr(.exportRules)) {
                    exportCSV()
                }
                Spacer()

                Text(l10n.tr(.rulesCount(rules.macroEntries.count)))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark
                    ? ZincPalette.zinc900.opacity(0.35)
                    : ZincPalette.zinc100.opacity(0.45)
            )
        }
        .frame(minWidth: 500, minHeight: 340)
        .background(GlassBackgroundView().ignoresSafeArea())
        .background(WindowAttachment(role: .macros, manager: model.windows))
        .navigationTitle(l10n.tr(.shorthandWindowTitle))
        .alert(
            l10n.tr(.invalidFileFormatTitle),
            isPresented: $showingErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func binding(for entry: MacroEntry) -> Binding<MacroEntry> {
        Binding(
            get: {
                rules.macroEntries.first(where: { $0.id == entry.id }) ?? entry
            },
            set: { updated in
                rules.updateMacro(updated)
            }
        )
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = l10n.tr(.exportRules)
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyy"
        let dateStr = formatter.string(from: Date())
        panel.nameFieldStringValue = "daukey-shortcuts-\(dateStr).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let content = rules.exportMacrosCSV()
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = l10n.tr(.importRules)
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                showError(l10n.tr(.cannotReadFileMessage))
                return
            }
            do {
                try rules.importMacrosCSV(content)
            } catch {
                // Every import error is a file that is not two non-empty columns per record.
                showError(l10n.tr(.invalidFileFormatMessage))
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}
