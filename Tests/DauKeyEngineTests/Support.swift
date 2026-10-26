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

/// The text a composition of `keys` displays.
func composed(_ keys: String, _ options: Options = Options()) -> String {
    Composer(options: options).display(Array(keys))
}

extension Options {
    static let vni = Options(inputMethod: .vni)
    static let modern = Options(toneStyle: .modern)
    static let check = Options(spelling: .check)
    static let off = Options(spelling: .off)
    static let vniOff = Options(inputMethod: .vni, spelling: .off)

    /// All 36 option combinations.
    static let all: [Options] = InputMethod.allCases.flatMap { method in
        ToneStyle.allCases.flatMap { style in
            Spelling.allCases.flatMap { spelling in
                [false, true].map { foreign in
                    Options(inputMethod: method, toneStyle: style, spelling: spelling, allowForeignConsonants: foreign)
                }
            }
        }
    }
}

/// Types a key script into a fresh engine and returns the simulated screen.
func typed(_ script: String, _ options: Options = Options()) -> String {
    Typist.type(script, options: options)
}
