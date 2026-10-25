extension Composer {
    /// Spec §5.4.
    func applyCircumflex(_ bases: Set<UInt8>, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        let region = Region.of(w.elements)
        var candidates: [Candidate] = []
        if let region {
            for index in region.reversed() {
                guard let letter = w.letter(index), bases.contains(letter.base),
                      letter.modifier == .none || letter.modifier == .breve || letter.modifier == .horn
                else { continue }
                var candidate = w
                set(.circumflex, at: index, in: &candidate, key: position)
                candidates.append(Candidate(result: candidate))
            }
        }
        if let chosen = choose(candidates, from: w) {
            w = chosen
            return
        }
        if let region, undoAllowed(w),
           let index = region.reversed().first(where: { index in
               guard let letter = w.letter(index) else { return false }
               return bases.contains(letter.base) && letter.modifier == .circumflex
           }) {
            let cancelled = resetModifier(at: index, in: &w)
            appendUndo(key, lower: lower, cancelled: cancelled, to: &w, at: position)
            return
        }
        append(key, to: &w, at: position)
    }

    /// Spec §5.6. "First letter" skips `other` elements; the mid-word candidate looks at the last element.
    func applyStroke(to w: inout Composition, key: Character, lower: Character, at position: Int) {
        let firstLetter = w.slots.indices.first { w.letter($0) != nil }
        var candidates: [Candidate] = []
        if let firstLetter, let first = w.letter(firstLetter), first.base == ASCII.d, first.modifier == .none {
            var candidate = w
            set(.stroke, at: firstLetter, in: &candidate, key: position)
            candidates.append(Candidate(result: candidate))
        }
        let last = w.slots.count - 1
        if last > 0, last != firstLetter, let letter = w.letter(last), letter.base == ASCII.d, letter.modifier == .none,
           w.letter(last - 1)?.isVowel != true {
            var candidate = w
            set(.stroke, at: last, in: &candidate, key: position)
            candidate.midWordStroke = true
            candidates.append(Candidate(result: candidate, alwaysPasses: true))
        }
        if let chosen = choose(candidates, from: w) {
            w = chosen
            w.spellingOffByStroke = true
            return
        }
        // A mid-word stroke starts its own segment, so a stroked letter is always the first letter of its segment.
        if let firstLetter, w.letter(firstLetter)?.modifier == .stroke, undoAllowed(w) {
            let cancelled = resetModifier(at: firstLetter, in: &w)
            appendUndo(key, lower: lower, cancelled: cancelled, to: &w, at: position)
            return
        }
        append(key, to: &w, at: position)
    }
}
