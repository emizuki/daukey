import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MacroSettingsView: View {
    @State private var store = MacroStore.shared
    @State private var selection = Set<MacroEntry.ID>()
    @State private var l10n = LocalizationManager.shared
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) private var colorScheme

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
                ForEach(store.entries) { entry in
                    TableRow(entry)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 8) {
                Button {
                    let newId = store.addEntry()
                    selection = [newId]
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help(l10n.tr(.addRuleHelp))

                Button {
                    store.remove(ids: selection)
                    selection.removeAll()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(selection.isEmpty ? 0.02 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(selection.isEmpty)
                .help(l10n.tr(.deleteRulesHelp))

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)

                Button {
                    importCSV()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help(l10n.tr(.importRules))

                Button {
                    exportCSV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help(l10n.tr(.exportRules))

                Spacer()

                Text(l10n.tr(.rulesCount(store.entries.count)))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(GlassBackgroundView().ignoresSafeArea())
        }
        .frame(minWidth: 500, minHeight: 340)
        .background(GlassBackgroundView().ignoresSafeArea())
        .navigationTitle(l10n.tr(.shorthandWindowTitle))
        .alert(
            l10n.tr(.invalidFileFormatTitle),
            isPresented: $showingErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            WindowLifecycleManager.windowOpened("macros")
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            store.save()
            WindowLifecycleManager.windowClosed("macros")
        }
        .onChange(of: store.entries) { _, _ in
            store.save()
        }
    }

    private func binding(for entry: MacroEntry) -> Binding<MacroEntry> {
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
        panel.nameFieldStringValue = "daukey-shortcuts-\(dateStr).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
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
            guard let items = MacroStore.validateAndParseCSV(content) else {
                showError(l10n.tr(.invalidFileFormatMessage))
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
