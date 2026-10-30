/// Which onsets count as valid (spec §7.1).
enum OnsetSet: Int, Sendable, CaseIterable {
    case native
    case foreignTelex
    case foreignVNI

    init(_ options: Options) {
        if !options.allowForeignConsonants {
            self = .native
        } else {
            switch options.inputMethod {
            case .telex, .simpleTelex: self = .foreignTelex
            case .vni: self = .foreignVNI
            }
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

    /// A syllable accepted although the tables reject it: exact letters and tone, with its split.
    struct Exception: Sendable {
        let glyphs: [UInt8]
        let tone: Tone
        let split: Split
    }

    /// Spelling, tone, onset letters, nucleus letters; the coda is the rest. The nucleus is the last vowel run.
    /// Source: Cục Thống kê administrative-unit list, queried 2026-10-30 for 30/06/2025 and 30/10/2026; design §3.
    /// The last four are loanwords and colloquial forms.
    private static let exceptionData: [(String, Tone, Int, Int)] = [
        ("avương", .none, 2, 2),  // avương
        ("bhăng", .none, 2, 1),  // bhăng
        ("bhôk", .acute, 2, 1),  // bhốk
        ("bla", .grave, 2, 1),  // blà
        ("blô", .none, 2, 1),  // blô
        ("blư", .acute, 2, 1),  // blứ
        ("broăi", .none, 2, 3),  // broăi
        ("buk", .acute, 1, 1),  // búk
        ("bă", .none, 1, 1),  // bă
        ("băh", .none, 1, 1),  // băh
        ("chrôh", .none, 3, 1),  // chrôh
        ("cuôr", .none, 1, 2),  // cuôr
        ("djrăng", .none, 3, 1),  // djrăng
        ("dliê", .none, 2, 2),  // dliê
        ("drênh", .none, 2, 1),  // drênh
        ("droh", .acute, 2, 1),  // dróh
        ("drot", .acute, 2, 1),  // drót
        ("drô", .none, 2, 1),  // drô
        ("drông", .none, 2, 1),  // drông
        ("drăm", .none, 2, 1),  // drăm
        ("drăng", .none, 2, 1),  // drăng
        ("drăk", .acute, 2, 1),  // drắk
        ("dêr", .none, 1, 1),  // dêr
        ("dêê", .none, 1, 2),  // dêê
        ("dăh", .none, 1, 1),  // dăh
        ("dơk", .none, 1, 1),  // dơk
        ("dơng", .none, 1, 1),  // dơng
        ("eacha", .grave, 4, 1),  // eachà
        ("grăng", .none, 2, 1),  // grăng
        ("hlôp", .acute, 2, 1),  // hlốp
        ("hru", .acute, 2, 1),  // hrú
        ("jlơi", .none, 2, 2),  // jlơi
        ("jut", .acute, 1, 1),  // jút
        ("jơ", .none, 1, 1),  // jơ
        ("kbô", .none, 2, 1),  // kbô
        ("kdăm", .none, 2, 1),  // kdăm
        ("khăl", .none, 2, 1),  // khăl
        ("khơng", .none, 2, 1),  // khơng
        ("khươl", .none, 2, 2),  // khươl
        ("klông", .none, 2, 1),  // klông
        ("kmut", .acute, 2, 1),  // kmút
        ("kmăl", .none, 2, 1),  // kmăl
        ("knuêc", .acute, 2, 2),  // knuếc
        ("knôp", .acute, 2, 1),  // knốp
        ("knơ", .acute, 2, 1),  // knớ
        ("kriêng", .none, 2, 2),  // kriêng
        ("krai", .acute, 2, 2),  // krái
        ("krêl", .none, 2, 1),  // krêl
        ("krêy", .none, 2, 2),  // krêy
        ("krông", .none, 2, 1),  // krông
        ("kuêh", .none, 1, 2),  // kuêh
        ("kot", .acute, 1, 1),  // kót
        ("kô", .none, 1, 1),  // kô
        ("kôi", .none, 1, 2),  // kôi
        ("kôn", .none, 1, 1),  // kôn
        ("kông", .none, 1, 1),  // kông
        ("kơ", .none, 1, 1),  // kơ
        ("kơi", .none, 1, 2),  // kơi
        ("kan", .dot, 1, 1),  // kạn
        ("kân", .grave, 1, 1),  // kần
        ("laêê", .none, 1, 3),  // laêê
        ("lơng", .none, 1, 1),  // lơng
        ("lăk", .acute, 1, 1),  // lắk
        ("miâu", .grave, 1, 3),  // miầu
        ("mlah", .acute, 2, 1),  // mláh
        ("môl", .none, 1, 1),  // môl
        ("măih", .none, 1, 2),  // măih
        ("ngok", .dot, 2, 1),  // ngọk
        ("nuôl", .none, 1, 2),  // nuôl
        ("piơr", .none, 1, 2),  // piơr
        ("plô", .none, 2, 1),  // plô
        ("plông", .none, 2, 1),  // plông
        ("pnôn", .none, 2, 1),  // pnôn
        ("prông", .none, 2, 1),  // prông
        ("pek", .acute, 1, 1),  // pék
        ("puch", .acute, 1, 1),  // púch
        ("păh", .none, 1, 1),  // păh
        ("păl", .none, 1, 1),  // păl
        ("pơnan", .none, 3, 1),  // pơnan
        ("pơng", .none, 1, 1),  // pơng
        ("pơơ", .none, 1, 2),  // pơơ
        ("pưh", .none, 1, 1),  // pưh
        ("pôk", .acute, 1, 1),  // pốk
        ("rcăm", .none, 2, 1),  // rcăm
        ("rsươm", .none, 2, 2),  // rsươm
        ("rtô", .none, 2, 1),  // rtô
        ("rvê", .none, 2, 1),  // rvê
        ("rơng", .none, 1, 1),  // rơng
        ("rôk", .acute, 1, 1),  // rốk
        ("sro", .acute, 2, 1),  // sró
        ("srônh", .none, 2, 1),  // srônh
        ("sôr", .none, 1, 1),  // sôr
        ("sơmei", .none, 3, 2),  // sơmei
        ("săk", .acute, 1, 1),  // sắk
        ("tih", .acute, 1, 1),  // tíh
        ("toh", .acute, 1, 1),  // tóh
        ("tôr", .none, 1, 1),  // tôr
        ("teh", .hook, 1, 1),  // tẻh
        ("val", .grave, 1, 1),  // vàl
        ("xiêr", .none, 1, 2),  // xiêr
        ("yiêng", .none, 0, 3),  // yiêng
        ("yông", .none, 0, 2),  // yông
        ("yă", .none, 0, 2),  // yă
        ("zuôich", .none, 1, 3),  // zuôich
        ("êbur", .none, 2, 1),  // êbur
        ("êê", .none, 0, 2),  // êê
        ("buyp", .acute, 1, 2),  // buýp
        ("buyt", .acute, 1, 2),  // buýt
        ("moa", .acute, 1, 2),  // móa
        ("moa", .hook, 1, 2),  // mỏa
    ]

    /// Syllables valid although the tables reject them, matched on exact letters and tone (spec §7.5).
    static let exceptions: [Exception] = exceptionData.map { spelling, tone, onset, nucleus in
        let glyphs = Glyph.codes(spelling)
        return Exception(glyphs: glyphs, tone: tone,
                         split: Split(onset: onset, nucleus: nucleus, coda: glyphs.count - onset - nucleus))
    }

    private struct ExceptionKey: Hashable {
        let glyphs: [UInt8]
        let tone: Tone
    }

    private static let exceptionSplits: [ExceptionKey: Split] = Dictionary(
        uniqueKeysWithValues: exceptions.map { (ExceptionKey(glyphs: $0.glyphs, tone: $0.tone), $0.split) }
    )

    /// The split of the exception with exactly these letters and tone, if any.
    static func exception(_ glyphs: [UInt8], tone: Tone) -> Split? {
        exceptionSplits[ExceptionKey(glyphs: glyphs, tone: tone)]
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

    /// The valid split with the longest onset, else the exception's split, or nil when the letters are not a valid
    /// syllable.
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
        return exception(glyphs, tone: tone)
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
