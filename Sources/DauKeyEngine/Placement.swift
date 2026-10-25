/// Chooses the letter that carries the tone (spec §8).
enum Placement {
    private static let oa = Glyph.codes("oa")
    private static let oe = Glyph.codes("oe")
    private static let uy = Glyph.codes("uy")

    /// Glyph codes of the elements, or nil when any element is not a letter.
    static func glyphs(_ elements: [Element]) -> [UInt8]? {
        var glyphs: [UInt8] = []
        glyphs.reserveCapacity(elements.count)
        for element in elements {
            guard let letter = element.letter else { return nil }
            glyphs.append(letter.glyph)
        }
        return glyphs
    }

    static func target(_ elements: [Element], tone: Tone, style: ToneStyle, onsets: OnsetSet) -> Int? {
        if let glyphs = glyphs(elements), let split = Orthography.split(glyphs, tone: tone, onsets: onsets) {
            let nucleus = Array(split.onset..<(split.onset + split.nucleus))
            return pick(nucleus, glyphs: glyphs, hasCoda: split.coda > 0, style: style)
        }
        guard let region = Region.of(elements) else { return nil }
        let end = region.upperBound
        var start = end
        while start > region.lowerBound, elements[start - 1].letter?.isVowel == true { start -= 1 }
        let hasCoda = elements[(end + 1)...].contains { $0.letter != nil }
        let codes = elements.map { $0.letter?.glyph ?? 0 }
        return pick(Array(start...end), glyphs: codes, hasCoda: hasCoda, style: style)
    }

    private static func pick(_ nucleus: [Int], glyphs: [UInt8], hasCoda: Bool, style: ToneStyle) -> Int {
        if let modified = nucleus.last(where: { Glyph.isModifiedVowel(glyphs[$0]) }) { return modified }
        if hasCoda { return nucleus[nucleus.count - 1] }
        if nucleus.count >= 3 { return nucleus[1] }
        if nucleus.count == 2 {
            let pair = nucleus.map { glyphs[$0] }
            if pair == oa || pair == oe || pair == uy { return style == .old ? nucleus[0] : nucleus[1] }
        }
        return nucleus[0]
    }
}
