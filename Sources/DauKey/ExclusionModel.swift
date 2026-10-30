import Foundation

/// An exclusion row as the editor shows and saves it; it may be a draft that does not apply yet.
public struct ExclusionEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var word: String

    public init(id: UUID = UUID(), word: String) {
        self.id = id
        self.word = word
    }
}
