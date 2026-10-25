/// Which onsets count as valid (spec §7.1).
enum OnsetSet: Int, Sendable, CaseIterable {
    case native
    case foreignTelex
    case foreignVNI

    init(_ options: Options) {
        if !options.allowForeignConsonants {
            self = .native
        } else {
            self = options.inputMethod == .telex ? .foreignTelex : .foreignVNI
        }
    }
}

/// Letter counts of the onset, nucleus and coda of a valid syllable.
struct Split: Equatable, Sendable {
    let onset: Int
    let nucleus: Int
    let coda: Int
}

enum Orthography {
    struct Nucleus: Sendable {
        let codes: [UInt8]
        /// May end the syllable without a coda.
        let open: Bool
        /// Codas allowed after this nucleus.
        let codas: [[UInt8]]
        /// Replaces `codas` after the onset `qu`, when present.
        let quCodas: [[UInt8]]?
    }

    private static let nativeOnsets = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m",
        "n", "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x",
    ]

    private static let onsetTables: [[[UInt8]]] = OnsetSet.allCases.map { set in
        var spellings = nativeOnsets
        switch set {
        case .native: break
        case .foreignTelex: spellings += ["z", "f", "j"]
        case .foreignVNI: spellings += ["z", "f", "j", "w"]
        }
        return spellings.map(Glyph.codes).sorted { $0.count > $1.count }
    }

    /// Onsets for the set, longest first.
    static func onsets(_ set: OnsetSet) -> [[UInt8]] { onsetTables[set.rawValue] }

    static let codas: [[UInt8]] = ["c", "ch", "m", "n", "ng", "nh", "p", "t"].map(Glyph.codes)
    static let stopCodas: [[UInt8]] = ["c", "ch", "p", "t"].map(Glyph.codes)

    /// The 56 nuclei of spec §7.1 with the coda table of §7.2, longest first.
    static let nuclei: [Nucleus] = {
        func spellings(_ list: String) -> [[UInt8]] {
            list.split(separator: " ").map { Glyph.codes(String($0)) }
        }
        func nucleus(_ spelling: String, open: Bool, _ codas: String = "", qu: String? = nil) -> Nucleus {
            Nucleus(codes: Glyph.codes(spelling), open: open, codas: spellings(codas), quCodas: qu.map(spellings))
        }
        let all = "c ch m n ng nh p t"
        let common = "c m n ng p t"
        let front = "ch m n nh p t"
        var list: [Nucleus] = [
            nucleus("a", open: true, all), nucleus("oa", open: true, all),
            nucleus("e", open: true, common), nucleus("o", open: true, common),
            nucleus("ô", open: true, common), nucleus("u", open: true, common),
            nucleus("ă", open: false, common), nucleus("â", open: false, common),
            nucleus("iê", open: false, common), nucleus("ươ", open: false, common),
            nucleus("ê", open: true, front), nucleus("i", open: true, front),
            nucleus("ơ", open: true, "m n p t"), nucleus("oo", open: false, "c ng"),
            nucleus("ư", open: true, "c m n ng t"), nucleus("uô", open: false, "c m n ng t"),
            nucleus("oă", open: false, "c m n ng t"), nucleus("oe", open: true, "c m n ng t"),
            nucleus("y", open: true, "t", qu: "n nh t"),
            nucleus("uy", open: true, "ch n nh p t"),
            nucleus("uê", open: true, "ch n nh"),
            nucleus("yê", open: false, "m n ng t"),
            nucleus("uâ", open: false, "n ng t"),
            nucleus("uyê", open: false, "n t"),
        ]
        let openOnly = "ai ao au ay âu ây eo êu ia iu oi ôi ơi ui ưi ưu ua ưa uơ iêu yêu oai oay oao oeo uêu uôi ươi ươu uây uya uyu"
        for spelling in openOnly.split(separator: " ") {
            list.append(nucleus(String(spelling), open: true))
        }
        return list.sorted { $0.codes.count > $1.codes.count }
    }()

    private static let qu = Glyph.codes("qu")
    private static let gi = Glyph.codes("gi")
    private static let plainU: UInt8 = 21
    private static let plainI: UInt8 = 9

    static func isValid(onset: [UInt8], nucleus: Nucleus, coda: [UInt8], tone: Tone) -> Bool {
        let first = Glyph.base(of: nucleus.codes[0])
        if onset == qu && first == plainU { return false }
        if onset == gi && first == plainI { return false }
        if coda.isEmpty { return nucleus.open }
        let allowed = (onset == qu ? nucleus.quCodas : nil) ?? nucleus.codas
        guard allowed.contains(coda) else { return false }
        if stopCodas.contains(coda) && (tone == .grave || tone == .hook || tone == .tilde) { return false }
        return true
    }

    /// The valid split with the longest onset, or nil when the letters are not a valid syllable.
    static func split(_ glyphs: [UInt8], tone: Tone, onsets set: OnsetSet) -> Split? {
        for onset in onsets(set) where glyphs.starts(with: onset) {
            let rest = glyphs.dropFirst(onset.count)
            for nucleus in nuclei where rest.starts(with: nucleus.codes) {
                let coda = Array(rest.dropFirst(nucleus.codes.count))
                if isValid(onset: onset, nucleus: nucleus, coda: coda, tone: tone) {
                    return Split(onset: onset.count, nucleus: nucleus.codes.count, coda: coda.count)
                }
            }
        }
        return nil
    }
}

/// The nucleus region of spec §5.2: first to last vowel letter, without the `u` of `qu` or the `i` of `gi`.
enum Region {
    static func of(_ elements: [Element]) -> ClosedRange<Int>? {
        let vowels = elements.indices.filter { elements[$0].letter?.isVowel == true }
        guard let first = vowels.first, let last = vowels.last else { return nil }
        var start = 0
        if first > 0, let letter = elements[first].letter, let previous = elements[first - 1].letter {
            let vowelFollows = first + 1 < elements.count && elements[first + 1].letter?.isVowel == true
            if (letter.base == ASCII.u && previous.base == ASCII.q)
                || (letter.base == ASCII.i && previous.base == ASCII.g && vowelFollows) {
                start = 1
            }
        }
        guard start < vowels.count else { return nil }
        return vowels[start]...last
    }
}
