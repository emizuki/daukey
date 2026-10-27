import Foundation
import Observation

public struct ExclusionEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var word: String

    public init(id: UUID = UUID(), word: String) {
        self.id = id
        self.word = word
    }
}

@MainActor @Observable
public final class ExclusionStore {
    public static let shared = ExclusionStore()
    public var entries: [ExclusionEntry] = []
    private let defaults: UserDefaults

    public var exclusionSet: Set<String> {
        Set(entries.map { $0.word.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !$0.contains(where: \.isWhitespace) })
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func load() {
        guard let data = defaults.data(forKey: "exclusionEntries"),
              let decoded = try? JSONDecoder().decode([ExclusionEntry].self, from: data) else {
            self.entries = [
                ExclusionEntry(word: "code"),
                ExclusionEntry(word: "docker"),
                ExclusionEntry(word: "admin"),
            ]
            return
        }
        self.entries = decoded
    }

    public func save() {
        let sanitized = entries.filter {
            let trimmed = $0.word.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.contains(where: \.isWhitespace)
        }
        if let encoded = try? JSONEncoder().encode(sanitized) {
            defaults.set(encoded, forKey: "exclusionEntries")
        }
        NotificationCenter.default.post(name: Notification.Name("daukeySyncData"), object: nil)
    }

    @discardableResult
    public func addEntry() -> ExclusionEntry.ID {
        let new = ExclusionEntry(word: "")
        entries.append(new)
        save()
        return new.id
    }

    public func remove(ids: Set<ExclusionEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - CSV Export & Import

    public func exportCSVContent() -> String {
        let valid = entries.map { $0.word.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains(where: \.isWhitespace) }
        return valid.map { MacroStore.escapeCSV($0) }.joined(separator: "\n")
    }

    public static func validateAndParseCSV(_ text: String) -> [String]? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var results: [String] = []
        for line in lines {
            let cols = MacroStore.parseCSVLine(line)
            guard let first = cols.first?.trimmingCharacters(in: .whitespaces),
                  !first.isEmpty, !first.contains(where: \.isWhitespace) else { return nil }
            results.append(first)
        }
        return results
    }

    public func importCSVItems(_ items: [String]) {
        for word in items {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.contains(where: \.isWhitespace) else { continue }
            if !entries.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) {
                entries.append(ExclusionEntry(word: trimmed))
            }
        }
        save()
    }
}
