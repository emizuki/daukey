extension Composer {
    /// Spec §5.5. Telex `w` passes horn and breve; VNI `7` horn only; VNI `8` breve only.
    func applyHornBreve(horn: Bool, breve: Bool, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        let region = Region.of(w.elements)
        var candidates: [Candidate] = []
        if let region {
            if horn, let pair = pairCandidate(w, region) {
                var candidate = w
                set(.horn, at: pair.0, in: &candidate, key: position)
                set(.horn, at: pair.1, in: &candidate, key: position)
                candidates.append(Candidate(result: candidate))
            }
            for index in region.reversed() {
                guard let letter = w.letter(index), letter.modifier == .none || letter.modifier == .circumflex else { continue }
                if breve && letter.base == ASCII.a {
                    var candidate = w
                    set(.breve, at: index, in: &candidate, key: position)
                    candidates.append(Candidate(result: candidate))
                } else if horn && (letter.base == ASCII.o || letter.base == ASCII.u) {
                    var candidate = w
                    set(.horn, at: index, in: &candidate, key: position)
                    candidates.append(Candidate(result: candidate))
                }
            }
        }
        if let chosen = choose(candidates, from: w) {
            w = chosen
            return
        }
        if let region, undoAllowed(w) {
            let targets = region.filter { index in
                guard let modifier = w.letter(index)?.modifier else { return false }
                return (horn && modifier == .horn) || (breve && modifier == .breve)
            }
            if targets.count == 1, let source = w.letter(targets[0])?.source, source.lowercased() == "w" {
                let index = targets[0]
                w.slots[index] = Slot(element: sourceElement(source), own: w.slots[index].own + w.slots[index].mods + [position])
                w.escaped.insert(lower)
                dropToneIfRegionEmpty(&w, into: index)
                return
            }
            if !targets.isEmpty {
                var cancelled: [Int] = []
                for index in targets { cancelled += resetModifier(at: index, in: &w) }
                appendUndo(key, lower: lower, cancelled: cancelled, to: &w, at: position)
                return
            }
        }
        if horn && breve {
            var candidate = w
            let letter = Letter(base: ASCII.u, modifier: .horn, uppercase: key.isUppercase, source: key)
            candidate.slots.append(Slot(element: .letter(letter), own: [position]))
            if isCompletable(candidate) {
                w = candidate
                return
            }
        }
        append(key, to: &w, at: position)
    }

    /// The rightmost `(u|ư)(o|ô|ơ)` pair that is not already `ươ`, except a final plain pair after the onset `th`.
    private func pairCandidate(_ w: Composition, _ region: ClosedRange<Int>) -> (Int, Int)? {
        guard region.count >= 2 else { return nil }
        for index in stride(from: region.upperBound - 1, through: region.lowerBound, by: -1) {
            guard let u = w.letter(index), let o = w.letter(index + 1),
                  u.base == ASCII.u, o.base == ASCII.o,
                  !(u.modifier == .horn && o.modifier == .horn)
            else { continue }
            let isFinal = index + 1 == w.slots.count - 1
            let afterTH = region.lowerBound == 2 && w.letter(0)?.base == ASCII.t && w.letter(1)?.base == ASCII.h
            if isFinal && u.modifier == .none && afterTH { continue }
            return (index, index + 1)
        }
        return nil
    }

    /// Spec §5.8.
    func applyBracket(base: UInt8, uppercase: Bool, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        let last = w.slots.count - 1
        if last >= 0, w.letter(last)?.source == key, undoAllowed(w) {
            w.slots[last] = Slot(element: .other(key), own: w.slots[last].own + w.slots[last].mods + [position])
            w.escaped.insert(lower)
            dropToneIfRegionEmpty(&w, into: last)
            return
        }
        var candidate = w
        let letter = Letter(base: base, modifier: .horn, uppercase: uppercase, source: key)
        candidate.slots.append(Slot(element: .letter(letter), own: [position]))
        if isCompletable(candidate) {
            w = candidate
            return
        }
        w.lastKeyBroke = true
    }
}
