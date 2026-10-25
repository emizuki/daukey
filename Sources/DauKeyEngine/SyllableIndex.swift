/// Answers "can these letters still become a valid syllable?" (spec §7.3) in O(letters).
///
/// Every prefix of every valid syllable is stored, once with its tone and once without, in every
/// variant where modified letters are replaced by their plain base (so `tien` matches `tiên`).
struct SyllableIndex: Sendable {
    private let keys: Set<UInt64>

    private static let native = SyllableIndex(.native)
    private static let foreignTelex = SyllableIndex(.foreignTelex)
    private static let foreignVNI = SyllableIndex(.foreignVNI)

    static func `for`(_ set: OnsetSet) -> SyllableIndex {
        switch set {
        case .native: return native
        case .foreignTelex: return foreignTelex
        case .foreignVNI: return foreignVNI
        }
    }

    private init(_ set: OnsetSet) {
        var keys = Set<UInt64>()
        let codaChoices: [[UInt8]] = [[]] + Orthography.codas
        for onset in Orthography.onsets(set) {
            for nucleus in Orthography.nuclei {
                for coda in codaChoices {
                    for tone in Tone.allCases
                    where Orthography.isValid(onset: onset, nucleus: nucleus, coda: coda, tone: tone) {
                        let full = onset + nucleus.codes + coda
                        for length in 0...full.count {
                            Self.insertVariants(of: Array(full.prefix(length)), tone: tone, into: &keys)
                        }
                    }
                }
            }
        }
        self.keys = keys
    }

    private static func insertVariants(of prefix: [UInt8], tone: Tone, into keys: inout Set<UInt64>) {
        let modified = prefix.indices.filter { Glyph.isModified(prefix[$0]) }
        for mask in 0..<(1 << modified.count) {
            var variant = prefix
            for (bit, position) in modified.enumerated() where mask & (1 << bit) != 0 {
                variant[position] = Glyph.base(of: variant[position])
            }
            keys.insert(key(variant, tone: tone))
            keys.insert(key(variant, tone: .none))
        }
    }

    /// Length in bits 0–3, tone in bits 4–6, then six bits per letter (at most eight letters).
    private static func key(_ glyphs: [UInt8], tone: Tone) -> UInt64 {
        var key = UInt64(glyphs.count) | UInt64(tone.rawValue) << 4
        for (position, glyph) in glyphs.enumerated() {
            key |= UInt64(glyph) << (7 + 6 * UInt64(position))
        }
        return key
    }

    func contains(_ glyphs: [UInt8], tone: Tone) -> Bool {
        glyphs.count <= 8 && keys.contains(Self.key(glyphs, tone: tone))
    }
}
