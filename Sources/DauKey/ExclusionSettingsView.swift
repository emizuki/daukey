import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExclusionSettingsView: View {
    @State private var store = ExclusionStore.shared
    @State private var selection = Set<ExclusionEntry.ID>()
    @State private var l10n = LocalizationManager.shared
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) private var colorScheme

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
                ForEach(store.entries) { entry in
                    TableRow(entry)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 8) {
                ToolbarIconButton(icon: "plus", helpText: l10n.tr(.addExclusionHelp)) {
                    let newId = store.addEntry()
                    selection = [newId]
                }

                ToolbarIconButton(icon: "minus", helpText: l10n.tr(.deleteExclusionHelp), isDisabled: selection.isEmpty) {
                    store.remove(ids: selection)
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

                Text(l10n.tr(.exclusionsCount(store.entries.count)))
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
        .navigationTitle(l10n.tr(.exclusionsWindowTitle))
        .alert(
            l10n.tr(.invalidFileFormatTitle),
            isPresented: $showingErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            WindowLifecycleManager.windowOpened("exclusions")
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            store.save()
            WindowLifecycleManager.windowClosed("exclusions")
        }
        .onChange(of: store.entries) { _, _ in
            store.save()
        }
    }

    private func binding(for entry: ExclusionEntry) -> Binding<ExclusionEntry> {
        Binding(
            get: {
                store.entries.first(where: { $0.id == entry.id }) ?? entry
            },
            set: { updated in
                if let index = store.entries.firstIndex(where: { $0.id == entry.id }) {
                    store.entries[index] = updated
                    store.save()
                }
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
            let content = store.exportCSVContent()
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
            guard let items = ExclusionStore.validateAndParseCSV(content) else {
                showError(l10n.tr(.invalidExclusionFileMessage))
                return
            }
            store.importCSVItems(items)
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}
