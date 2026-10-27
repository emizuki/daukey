import Foundation
import Observation

public struct MacroEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var trigger: String
    public var replacement: String

    public init(id: UUID = UUID(), trigger: String, replacement: String) {
        self.id = id
        self.trigger = trigger
        self.replacement = replacement
    }
}

@MainActor @Observable
public final class MacroStore {
    public static let shared = MacroStore()
    public var entries: [MacroEntry] = []
    private let defaults: UserDefaults

    public var macroMap: [String: String] {
        var dict: [String: String] = [:]
        for entry in entries {
            let t = entry.trigger.trimmingCharacters(in: .whitespaces).lowercased()
            let r = entry.replacement.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !t.contains(where: \.isWhitespace) && !r.isEmpty {
                dict[t] = r
            }
        }
        return dict
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func load() {
        guard let data = defaults.data(forKey: "macroEntries"),
              let decoded = try? JSONDecoder().decode([MacroEntry].self, from: data) else {
            self.entries = [
                MacroEntry(trigger: "vn", replacement: "Việt Nam"),
                MacroEntry(trigger: "hn", replacement: "Hà Nội"),
                MacroEntry(trigger: "sg", replacement: "Sài Gòn"),
            ]
            return
        }
        self.entries = decoded
    }

    public func save() {
        // Filter out empty rows when persisting
        let sanitized = entries.filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty || !$0.replacement.trimmingCharacters(in: .whitespaces).isEmpty }
        if let encoded = try? JSONEncoder().encode(sanitized) {
            defaults.set(encoded, forKey: "macroEntries")
        }
        NotificationCenter.default.post(name: Notification.Name("daukeySyncData"), object: nil)
    }

    @discardableResult
    public func addEntry() -> MacroEntry.ID {
        let new = MacroEntry(trigger: "", replacement: "")
        entries.append(new)
        save()
        return new.id
    }

    public func remove(ids: Set<MacroEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - CSV Export & Import

    public static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    public static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }

    public static func validateAndParseCSV(_ text: String) -> [(trigger: String, replacement: String)]? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var results: [(trigger: String, replacement: String)] = []
        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count >= 2 else { return nil }
            let trigger = cols[0].trimmingCharacters(in: .whitespaces)
            let replacement = cols[1].trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty && !trigger.contains(where: \.isWhitespace) && !replacement.isEmpty else { return nil }
            results.append((trigger: trigger, replacement: replacement))
        }
        return results
    }

    public func exportCSVContent() -> String {
        let validEntries = entries.filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty && !$0.replacement.trimmingCharacters(in: .whitespaces).isEmpty }
        return validEntries.map {
            "\(Self.escapeCSV($0.trigger)),\(Self.escapeCSV($0.replacement))"
        }.joined(separator: "\n")
    }

    public func importCSVItems(_ items: [(trigger: String, replacement: String)]) {
        for item in items {
            if let index = entries.firstIndex(where: { $0.trigger == item.trigger }) {
                entries[index].replacement = item.replacement
            } else {
                entries.append(MacroEntry(trigger: item.trigger, replacement: item.replacement))
            }
        }
        save()
    }
}
