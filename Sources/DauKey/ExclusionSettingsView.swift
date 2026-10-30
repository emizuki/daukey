import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExclusionSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<ExclusionEntry.ID>()
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) private var colorScheme

    private var rules: RuleEditorModel { model.rules }
    private var l10n: LocalizationManager { model.localization }

    var body: some View {
        VStack(spacing: 0) {
            Table(of: ExclusionEntry.self, selection: $selection) {
                TableColumn(l10n.tr(.exclusionColumn)) { entry in
                    TextField(l10n.tr(.exclusionPlaceholder), text: Binding(
                        get: { binding(for: entry).wrappedValue.word },
                        set: { binding(for: entry).wrappedValue.word = $0.filter { !$0.isWhitespace } }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                }
                .width(min: 240, ideal: 380)
            } rows: {
                ForEach(rules.exclusionEntries) { entry in
                    TableRow(entry)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 8) {
                ToolbarIconButton(icon: "plus", helpText: l10n.tr(.addExclusionHelp)) {
                    let newId = rules.addExclusion()
                    selection = [newId]
                }

                ToolbarIconButton(icon: "minus", helpText: l10n.tr(.deleteExclusionHelp), isDisabled: selection.isEmpty) {
                    rules.removeExclusions(selection)
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

                Text(l10n.tr(.exclusionsCount(rules.exclusionEntries.count)))
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
        .frame(minWidth: 460, minHeight: 340)
        .background(GlassBackgroundView().ignoresSafeArea())
        .background(WindowAttachment(role: .exclusions, manager: model.windows))
        .navigationTitle(l10n.tr(.exclusionsWindowTitle))
        .alert(
            l10n.tr(.invalidFileFormatTitle),
            isPresented: $showingErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func binding(for entry: ExclusionEntry) -> Binding<ExclusionEntry> {
        Binding(
            get: {
                rules.exclusionEntries.first(where: { $0.id == entry.id }) ?? entry
            },
            set: { updated in
                rules.updateExclusion(updated)
            }
        )
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = l10n.tr(.exportRules)
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyy"
        let dateStr = formatter.string(from: Date())
        panel.nameFieldStringValue = "daukey-excluded-\(dateStr).csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let content = rules.exportExclusionsCSV()
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
                try rules.importExclusionsCSV(content)
            } catch {
                // Every import error is a file that is not one single word per record.
                showError(l10n.tr(.invalidExclusionFileMessage))
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}
