extension Composer {
    /// Keys left after one Backspace on a composing word (spec §6.2).
    func keysAfterBackspace(_ keys: [Character]) -> [Character] {
        let w = compose(keys)
        guard let last = w.slots.indices.last else { return [] }
        var removed = Set(w.slots[last].own + w.slots[last].mods)
        for slot in w.earlier.flatMap(\.slots) + w.slots.dropLast() {
            removed.subtract(slot.own)
            removed.subtract(slot.mods)
        }
        if toneGroupHolder(w) == last {
            let remaining = Array(w.elements.dropLast())
            if isCompletable(w) || Region.of(remaining) == nil {
                removed.formUnion(w.toneKeys)
            }
        }
        var remaining = keys.indices.filter { !removed.contains($0) }.map { keys[$0] }
        // Removing a stroke can switch gating back on, so a bracket that resolved when it was typed may now be a
        // break character. Such a bracket was skipped by `compose`, so dropping it leaves the display unchanged.
        if options.inputMethod == .telex {
            var end = 1
            while end <= remaining.count {
                if "[]{}".contains(remaining[end - 1]), compose(Array(remaining.prefix(end))).lastKeyBroke {
                    remaining.remove(at: end - 1)
                } else {
                    end += 1
                }
            }
        }
        return remaining
    }

    /// The element the tone group is attached to (spec §6.1).
    func toneGroupHolder(_ w: Composition) -> Int? {
        if w.tone != .none { return toneCarrier(w) }
        return w.toneKeys.isEmpty ? nil : w.toneAnchor
    }
}
