/// Folds the keys of one word into a composition (spec §5) and renders it.
struct Composer: Sendable {
    let options: Options
    let onsets: OnsetSet
    let index: SyllableIndex

    init(options: Options) {
        self.options = options
        self.onsets = OnsetSet(options)
        self.index = SyllableIndex.`for`(onsets)
    }

    func compose(_ keys: [Character]) -> Composition {
        var w = Composition()
        for (position, key) in keys.enumerated() {
            step(&w, key: key, at: position)
        }
        return w
    }

    func render(_ w: Composition) -> String {
        var text = ""
        for segment in w.earlier {
            let elements = segment.slots.map(\.element)
            let at = segment.tone == .none ? nil : Placement.target(elements, tone: segment.tone, style: options.toneStyle, onsets: onsets)
            text += Render.string(elements, tone: segment.tone, toneAt: at)
        }
        return text + Render.string(w.elements, tone: w.tone, toneAt: w.tone == .none ? nil : toneCarrier(w))
    }

    func display(_ keys: [Character]) -> String { render(compose(keys)) }

    func toneCarrier(_ w: Composition) -> Int? {
        Placement.target(w.elements, tone: w.tone, style: options.toneStyle, onsets: onsets)
    }

    /// Spec §7.3, for the current segment. Ignoring the tone asks whether the letters alone can still be Vietnamese.
    func isCompletable(_ w: Composition, ignoringTone: Bool = false) -> Bool {
        guard let glyphs = Placement.glyphs(w.elements) else { return false }
        return index.contains(glyphs, tone: ignoringTone ? .none : w.tone)
    }

    func isValid(_ w: Composition) -> Bool {
        guard let glyphs = Placement.glyphs(w.elements) else { return false }
        return Orthography.split(glyphs, tone: w.tone, onsets: onsets) != nil
    }

    /// Spec §5.9.
    func spellingIsOff(_ w: Composition) -> Bool {
        options.spelling == .off || w.spellingOffByStroke
    }

    // MARK: Folding

    private func step(_ w: inout Composition, key: Character, at position: Int) {
        w.lastKeyBroke = false
        let escapedBefore = w.escaped.count
        let slotsBefore = w.slots.count
        let lower = Character(key.lowercased())
        if !w.escaped.contains(lower), let transform = Transform.lookup(lower, options.inputMethod) {
            apply(transform, to: &w, key: key, lower: lower, at: position)
        } else {
            append(key, to: &w, at: position)
        }
        if w.lastKeyBroke { return }
        normalise(&w)
        // Spec §5.9: every undo adds its key to `escaped`, and an undo turns spelling back on.
        if w.escaped.count > escapedBefore { w.spellingOffByStroke = false }
        if w.midWordStroke {
            w.midWordStroke = false
            startSegment(&w)
        } else if spellingIsOff(w), w.slots.count > slotsBefore, w.slots.count > 1,
                  w.slots.last?.element.letter != nil, !isCompletable(w, ignoringTone: true) {
            startSegment(&w)
        }
    }

    /// Closes the current segment before its last element, which starts the new current segment (spec §5.9).
    private func startSegment(_ w: inout Composition) {
        let letter = w.slots.removeLast()
        w.earlier.append(Segment(slots: w.slots, tone: w.tone, toneKeys: w.toneKeys, toneAnchor: w.toneAnchor))
        w.slots = [letter]
        w.tone = .none
        w.toneKeys = []
        w.toneAnchor = nil
        w.escaped = []
    }

    private func apply(_ transform: Transform, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        switch transform {
        case .tone(let tone): applyTone(tone, to: &w, key: key, lower: lower, at: position)
        case .removeTone: applyRemoveTone(to: &w, key: key, at: position)
        case .circumflex(let bases): applyCircumflex(bases, to: &w, key: key, lower: lower, at: position)
        case .hornBreve(let horn, let breve): applyHornBreve(horn: horn, breve: breve, to: &w, key: key, lower: lower, at: position)
        case .stroke: applyStroke(to: &w, key: key, lower: lower, at: position)
        case .bracket(let base, let uppercase): applyBracket(base: base, uppercase: uppercase, to: &w, key: key, lower: lower, at: position)
        }
    }

    // MARK: Shared helpers

    struct Candidate {
        var result: Composition
        var alwaysPasses = false
    }

    /// Picks a candidate (spec §5.1 "Choosing a candidate", §7.3 gating).
    func choose(_ candidates: [Candidate], from w: Composition, toneOnly: Bool = false) -> Composition? {
        let currentIsCompletable = toneOnly || isCompletable(w)
        return candidates.first { candidate in
            candidate.alwaysPasses || (currentIsCompletable && isCompletable(candidate.result))
        }?.result
    }

    func undoAllowed(_ w: Composition) -> Bool { isCompletable(w) }

    func append(_ key: Character, to w: inout Composition, at position: Int, extra: [Int] = []) {
        let element: Element = Letter(key: key).map(Element.letter) ?? .other(key)
        w.slots.append(Slot(element: element, own: [position] + extra))
    }

    func appendUndo(_ key: Character, lower: Character, cancelled: [Int], to w: inout Composition, at position: Int) {
        append(key, to: &w, at: position, extra: cancelled.sorted())
        w.escaped.insert(lower)
        dropToneIfRegionEmpty(&w, into: w.slots.count - 1)
    }

    /// Sets a letter's modifier for a key and records the key; a letter whose modifier does not change is
    /// left alone, so the key is not part of its provenance (spec §6.1 "every letter it changed").
    func set(_ modifier: Modifier, at position: Int, in w: inout Composition, key: Int) {
        guard var letter = w.slots[position].element.letter, letter.modifier != modifier else { return }
        letter.modifier = modifier
        letter.source = nil
        w.slots[position].element = .letter(letter)
        w.slots[position].mods.append(key)
    }

    /// Removes a letter's modifier, or reverts a sourced letter to its key, and returns the cancelled keys.
    func resetModifier(at position: Int, in w: inout Composition) -> [Int] {
        guard var letter = w.slots[position].element.letter else { return [] }
        let cancelled = w.slots[position].mods
        w.slots[position].mods = []
        if let source = letter.source {
            w.slots[position].element = sourceElement(source)
        } else {
            letter.modifier = .none
            w.slots[position].element = .letter(letter)
        }
        return cancelled
    }

    func sourceElement(_ source: Character) -> Element {
        Letter(key: source).map(Element.letter) ?? .other(source)
    }

    /// When no vowel is left to carry it, the tone is dropped and `T` joins the given slot.
    func dropToneIfRegionEmpty(_ w: inout Composition, into position: Int) {
        guard Region.of(w.elements) == nil, w.tone != .none || !w.toneKeys.isEmpty else { return }
        w.slots[position].own += w.toneKeys
        w.toneKeys = []
        w.tone = .none
        w.toneAnchor = nil
    }

    // MARK: Tones (spec §5.3)

    private func applyTone(_ tone: Tone, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        var candidates: [Candidate] = []
        if Region.of(w.elements) != nil, w.tone != tone {
            var candidate = w
            candidate.tone = tone
            candidate.toneKeys.append(position)
            candidate.toneAnchor = nil
            candidates.append(Candidate(result: candidate))
        }
        if let chosen = choose(candidates, from: w, toneOnly: true) {
            w = chosen
            return
        }
        if w.tone == tone, undoAllowed(w) {
            let cancelled = w.toneKeys
            w.tone = .none
            w.toneKeys = []
            w.toneAnchor = nil
            appendUndo(key, lower: lower, cancelled: cancelled, to: &w, at: position)
            return
        }
        append(key, to: &w, at: position)
    }

    private func applyRemoveTone(to w: inout Composition, key: Character, at position: Int) {
        var candidates: [Candidate] = []
        if w.tone != .none {
            var candidate = w
            candidate.toneAnchor = toneCarrier(w)
            candidate.tone = .none
            candidate.toneKeys.append(position)
            candidates.append(Candidate(result: candidate))
        }
        if let chosen = choose(candidates, from: w, toneOnly: true) {
            w = chosen
            return
        }
        append(key, to: &w, at: position)
    }

    // MARK: Horn normalisation (spec §5.1 step 3)

    private static let normaliseFollowers = Set("cimnptu".utf8)

    private func normalise(_ w: inout Composition) {
        guard w.slots.count >= 3 else { return }
        for position in 0..<(w.slots.count - 2) {
            guard var u = w.letter(position), var o = w.letter(position + 1), let next = w.letter(position + 2),
                  u.base == ASCII.u, o.base == ASCII.o,
                  (u.modifier == .none && o.modifier == .horn) || (u.modifier == .horn && o.modifier == .none),
                  Self.normaliseFollowers.contains(next.base),
                  !(position == 1 && w.letter(0)?.base == ASCII.q)
            else { continue }
            u.modifier = .horn
            o.modifier = .horn
            w.slots[position].element = .letter(u)
            w.slots[position + 1].element = .letter(o)
        }
    }
}
