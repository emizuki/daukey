import Testing
@testable import DauKeyEngine
import DauKeyScript

private let modifiedLetters: [Character: (Character, Modifier)] = [
    "ă": ("a", .breve), "â": ("a", .circumflex), "ê": ("e", .circumflex), "ô": ("o", .circumflex),
    "ơ": ("o", .horn), "ư": ("u", .horn), "đ": ("d", .stroke),
]

/// Builds elements from untoned Vietnamese text such as "ươn" or "Đ"; other characters become `.other`.
func elements(_ text: String) -> [Element] {
    text.map { character in
        let lower = Character(character.lowercased())
        if let pair = modifiedLetters[lower] {
            return .letter(Letter(base: pair.0.asciiValue!, modifier: pair.1, uppercase: character.isUppercase))
        }
        if let letter = Letter(key: character) { return .letter(letter) }
        return .other(character)
    }
}

/// Compares scalar by scalar, so a precomposed letter never matches its decomposed form.
func expectSameScalars(
    _ actual: String, _ expected: String, _ context: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        Array(actual.unicodeScalars) == Array(expected.unicodeScalars),
        "\(context) got \"\(actual)\", expected \"\(expected)\"",
        sourceLocation: sourceLocation
    )
}
