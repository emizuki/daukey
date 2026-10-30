import Foundation
import Observation
import DauKeyEngine

/// The one owner of the macro and exclusion rows the editors show, and of the tables compiled from them.
///
/// Rows are kept as entered, drafts included; `RuleTables` leaves out the rows that cannot apply. Each change saves
/// the rows and hands the new tables to `onChange` once.
@MainActor @Observable final class RuleEditorModel {
    enum ImportError: Error, Equatable {
        case noRecords
        /// Record `record`, counting from 1, has `found` columns instead of `expected`.
        case columnCount(record: Int, expected: Int, found: Int)
        /// Record `record`, counting from 1, is not a rule that can apply.
        case inactiveRule(record: Int)
        case malformed(CSVCodec.Error)
    }

    private(set) var macroEntries: [MacroEntry]
    private(set) var exclusionEntries: [ExclusionEntry]
    /// The tables compiled from the current rows.
    private(set) var tables: RuleTables
    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let onChange: (RuleTables) -> Void

    /// Loads the stored rows and compiles them; nothing is saved or emitted.
    init(store: PreferencesStore, onChange: @escaping (RuleTables) -> Void) {
        let rules = store.loadRules()
        macroEntries = rules.macros
        exclusionEntries = rules.exclusions
        tables = Self.compile(macros: rules.macros, exclusions: rules.exclusions)
        self.store = store
        self.onChange = onChange
    }

    // MARK: Macros

    @discardableResult func addMacro() -> UUID {
        let entry = MacroEntry(trigger: "", replacement: "")
        commit(macros: macroEntries + [entry], exclusions: exclusionEntries)
        return entry.id
    }

    /// Replaces the row with the same ID; an unknown ID or an unchanged row changes nothing.
    func updateMacro(_ entry: MacroEntry) {
        guard let index = macroEntries.firstIndex(where: { $0.id == entry.id }), macroEntries[index] != entry else {
            return
        }
        var macros = macroEntries
        macros[index] = entry
        commit(macros: macros, exclusions: exclusionEntries)
    }

    func removeMacros(_ ids: Set<UUID>) {
        let macros = macroEntries.filter { !ids.contains($0.id) }
        guard macros.count != macroEntries.count else { return }
        commit(macros: macros, exclusions: exclusionEntries)
    }

    /// Imports `trigger,replacement` records, all or none. In record order, each replaces the row the tables use for
    /// its key, keeping that row's ID and place and leaving earlier rows with the key and drafts as they are; a new
    /// key is appended.
    func importMacrosCSV(_ text: String) throws(ImportError) {
        let records = try Self.records(text, columns: 2)
        var macros = macroEntries
        var winners = Self.winners(macros, key: \.trigger, isActive: Self.isActive)
        for (index, record) in records.enumerated() {
            var entry = MacroEntry(trigger: record[0], replacement: record[1])
            guard Self.isActive(entry) else { throw .inactiveRule(record: index + 1) }
            let key = RuleTables.key(entry.trigger)
            if let winner = winners[key] {
                entry.id = macros[winner].id
                macros[winner] = entry
            } else {
                winners[key] = macros.count
                macros.append(entry)
            }
        }
        commit(macros: macros, exclusions: exclusionEntries)
    }

    /// The rows that apply, in table order.
    func exportMacrosCSV() -> String {
        CSVCodec.encode(macroEntries.filter(Self.isActive).map { [$0.trigger, $0.replacement] })
    }

    // MARK: Exclusions

    @discardableResult func addExclusion() -> UUID {
        let entry = ExclusionEntry(word: "")
        commit(macros: macroEntries, exclusions: exclusionEntries + [entry])
        return entry.id
    }

    /// Replaces the row with the same ID; an unknown ID or an unchanged row changes nothing.
    func updateExclusion(_ entry: ExclusionEntry) {
        guard let index = exclusionEntries.firstIndex(where: { $0.id == entry.id }), exclusionEntries[index] != entry
        else { return }
        var exclusions = exclusionEntries
        exclusions[index] = entry
        commit(macros: macroEntries, exclusions: exclusions)
    }

    func removeExclusions(_ ids: Set<UUID>) {
        let exclusions = exclusionEntries.filter { !ids.contains($0.id) }
        guard exclusions.count != exclusionEntries.count else { return }
        commit(macros: macroEntries, exclusions: exclusions)
    }

    /// Imports one-word records, all or none, merged like `importMacrosCSV`.
    func importExclusionsCSV(_ text: String) throws(ImportError) {
        let records = try Self.records(text, columns: 1)
        var exclusions = exclusionEntries
        var winners = Self.winners(exclusions, key: \.word, isActive: Self.isActive)
        for (index, record) in records.enumerated() {
            var entry = ExclusionEntry(word: record[0])
            guard Self.isActive(entry) else { throw .inactiveRule(record: index + 1) }
            let key = RuleTables.key(entry.word)
            if let winner = winners[key] {
                entry.id = exclusions[winner].id
                exclusions[winner] = entry
            } else {
                winners[key] = exclusions.count
                exclusions.append(entry)
            }
        }
        commit(macros: macroEntries, exclusions: exclusions)
    }

    /// The rows that apply, in table order.
    func exportExclusionsCSV() -> String {
        CSVCodec.encode(exclusionEntries.filter(Self.isActive).map { [$0.word] })
    }

    // MARK: Shared

    private func commit(macros: [MacroEntry], exclusions: [ExclusionEntry]) {
        macroEntries = macros
        exclusionEntries = exclusions
        tables = Self.compile(macros: macros, exclusions: exclusions)
        store.saveRules(macros: macros, exclusions: exclusions)
        onChange(tables)
    }

    private static func compile(macros: [MacroEntry], exclusions: [ExclusionEntry]) -> RuleTables {
        RuleTables(macros: macros.map { MacroRule(trigger: $0.trigger, replacement: $0.replacement) },
                   exclusions: exclusions.map(\.word))
    }

    /// Whether `RuleTables` keeps the row, so the rule applies unless a later row with the same key replaces it.
    private static func isActive(_ entry: MacroEntry) -> Bool {
        compile(macros: [entry], exclusions: []).replacement(for: entry.trigger) != nil
    }

    private static func isActive(_ entry: ExclusionEntry) -> Bool {
        compile(macros: [], exclusions: [entry]).excludes(entry.word)
    }

    /// Decodes every record and checks its column count before any row changes.
    private static func records(_ text: String, columns: Int) throws(ImportError) -> [[String]] {
        let records: [[String]]
        do {
            records = try CSVCodec.decode(text)
        } catch {
            throw .malformed(error)
        }
        guard !records.isEmpty else { throw .noRecords }
        for (index, record) in records.enumerated() where record.count != columns {
            throw .columnCount(record: index + 1, expected: columns, found: record.count)
        }
        return records
    }

    /// For each key, the index of the last active row with it: the row the tables use.
    private static func winners<Entry>(
        _ rows: [Entry], key: KeyPath<Entry, String>, isActive: (Entry) -> Bool
    ) -> [String: Int] {
        var winners: [String: Int] = [:]
        for (index, row) in rows.enumerated() where isActive(row) {
            winners[RuleTables.key(row[keyPath: key])] = index
        }
        return winners
    }
}
