import Foundation

/// A macro row as the editor shows and saves it; it may be a draft that does not apply yet.
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
