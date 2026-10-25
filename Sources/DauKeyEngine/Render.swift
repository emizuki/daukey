enum Render {
    /// Row in the tone tables for each vowel code.
    private static let vowelRows: [UInt8: Int] = [
        1: 0, Glyph.aBreve: 1, Glyph.aCircumflex: 2, 5: 3, Glyph.eCircumflex: 4, 9: 5,
        15: 6, Glyph.oCircumflex: 7, Glyph.oHorn: 8, 21: 9, Glyph.uHorn: 10, 25: 11,
    ]

    /// Columns: no tone, acute, grave, hook, tilde, dot. Every entry is one precomposed scalar.
    private static let lowercase: [[Character]] = [
        "aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
        "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ",
    ].map { Array($0) }

    private static let uppercase: [[Character]] = [
        "AÁÀẢÃẠ", "ĂẮẰẲẴẶ", "ÂẤẦẨẪẬ", "EÉÈẺẼẸ", "ÊẾỀỂỄỆ", "IÍÌỈĨỊ",
        "OÓÒỎÕỌ", "ÔỐỒỔỖỘ", "ƠỚỜỞỠỢ", "UÚÙỦŨỤ", "ƯỨỪỬỮỰ", "YÝỲỶỸỴ",
    ].map { Array($0) }

    static func character(_ letter: Letter, tone: Tone) -> Character {
        let code = letter.glyph
        if let row = vowelRows[code] {
            return (letter.uppercase ? uppercase : lowercase)[row][tone.rawValue]
        }
        if code == Glyph.dStroke { return letter.uppercase ? "Đ" : "đ" }
        return Character(Unicode.Scalar(letter.uppercase ? letter.base - 32 : letter.base))
    }

    static func string(_ elements: [Element], tone: Tone, toneAt index: Int?) -> String {
        var text = ""
        for (position, element) in elements.enumerated() {
            switch element {
            case .letter(let letter): text.append(character(letter, tone: position == index ? tone : .none))
            case .other(let character): text.append(character)
            }
        }
        return text
    }
}
