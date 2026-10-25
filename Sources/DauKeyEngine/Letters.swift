/// Byte values of the ASCII letters the rules refer to.
enum ASCII {
    static let a = UInt8(ascii: "a")
    static let d = UInt8(ascii: "d")
    static let e = UInt8(ascii: "e")
    static let g = UInt8(ascii: "g")
    static let h = UInt8(ascii: "h")
    static let i = UInt8(ascii: "i")
    static let o = UInt8(ascii: "o")
    static let q = UInt8(ascii: "q")
    static let t = UInt8(ascii: "t")
    static let u = UInt8(ascii: "u")
    static let w = UInt8(ascii: "w")
    static let y = UInt8(ascii: "y")
}

enum Modifier: UInt8, Sendable {
    case none, circumflex, horn, breve, stroke
}

enum Tone: Int, Sendable, CaseIterable {
    case none, acute, grave, hook, tilde, dot
}

struct Letter: Equatable, Sendable {
    /// Lowercase ASCII letter.
    var base: UInt8
    var modifier: Modifier
    var uppercase: Bool
    /// The key that created this letter when it is not the letter's own base: standalone `w`, or a bracket.
    var source: Character?

    init(base: UInt8, modifier: Modifier = .none, uppercase: Bool = false, source: Character? = nil) {
        self.base = base
        self.modifier = modifier
        self.uppercase = uppercase
        self.source = source
    }

    /// The plain letter typed by an ASCII letter key, or nil for any other key.
    init?(key: Character) {
        guard key.isASCII, key.isLetter, let value = key.asciiValue else { return nil }
        self.init(base: value | 0x20, uppercase: key.isUppercase)
    }

    var isVowel: Bool {
        base == ASCII.a || base == ASCII.e || base == ASCII.i || base == ASCII.o || base == ASCII.u || base == ASCII.y
    }

    var glyph: UInt8 { Glyph.code(base: base, modifier: modifier) }
}

enum Element: Equatable, Sendable {
    case letter(Letter)
    /// A VNI digit or a Telex bracket kept as text.
    case other(Character)

    var letter: Letter? {
        if case .letter(let letter) = self { return letter }
        return nil
    }
}

/// Case-free letter identity: 1–26 for plain a–z, 27–33 for ă â ê ô ơ ư đ.
enum Glyph {
    static let aBreve: UInt8 = 27
    static let aCircumflex: UInt8 = 28
    static let eCircumflex: UInt8 = 29
    static let oCircumflex: UInt8 = 30
    static let oHorn: UInt8 = 31
    static let uHorn: UInt8 = 32
    static let dStroke: UInt8 = 33

    static func code(base: UInt8, modifier: Modifier) -> UInt8 {
        switch (base, modifier) {
        case (_, .none): return base - 96
        case (ASCII.a, .breve): return aBreve
        case (ASCII.a, .circumflex): return aCircumflex
        case (ASCII.e, .circumflex): return eCircumflex
        case (ASCII.o, .circumflex): return oCircumflex
        case (ASCII.o, .horn): return oHorn
        case (ASCII.u, .horn): return uHorn
        case (ASCII.d, .stroke): return dStroke
        default: preconditionFailure("modifier \(modifier) is not valid on letter \(base)")
        }
    }

    /// The plain letter a code is built on: ă → a, ơ → o, đ → d.
    static func base(of code: UInt8) -> UInt8 {
        switch code {
        case aBreve, aCircumflex: return 1
        case eCircumflex: return 5
        case oCircumflex, oHorn: return 15
        case uHorn: return 21
        case dStroke: return 4
        default: return code
        }
    }

    static func isModified(_ code: UInt8) -> Bool { code >= aBreve }

    /// ă â ê ô ơ ư.
    static func isModifiedVowel(_ code: UInt8) -> Bool { code >= aBreve && code <= uHorn }

    /// Codes for lowercase untoned spelling such as "ươ" or "ngh".
    static func codes(_ text: String) -> [UInt8] {
        text.map { character in
            switch character {
            case "ă": return aBreve
            case "â": return aCircumflex
            case "ê": return eCircumflex
            case "ô": return oCircumflex
            case "ơ": return oHorn
            case "ư": return uHorn
            case "đ": return dStroke
            default: return character.asciiValue! - 96
            }
        }
    }
}
