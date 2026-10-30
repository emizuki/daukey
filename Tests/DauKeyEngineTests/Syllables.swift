import Foundation
@testable import DauKeyEngine

/// A syllable built from spec §7 tables, transcribed here independently of the engine.
struct Syllable: Hashable, Sendable {
    let onset: String
    let nucleus: String
    let coda: String
    let tone: Tone
    var letters: String { onset + nucleus + coda }
}

enum Syllables {
    static let onsets = ["", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng",
                         "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"]

    /// (nucleus, open, codas when closed).
    static let nuclei: [(String, Bool, [String])] = {
        let all = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]
        let common = ["c", "m", "n", "ng", "p", "t"]
        let front = ["ch", "m", "n", "nh", "p", "t"]
        var table: [(String, Bool, [String])] = [
            ("a", true, all), ("oa", true, all),
            ("e", true, common), ("o", true, common), ("ô", true, common), ("u", true, common),
            ("ă", false, common), ("â", false, common), ("iê", false, common), ("ươ", false, common),
            ("ê", true, front), ("i", true, front), ("ơ", true, ["m", "n", "p", "t"]), ("oo", false, ["c", "ng"]),
            ("ư", true, ["c", "m", "n", "ng", "t"]), ("uô", false, ["c", "m", "n", "ng", "t"]),
            ("oă", false, ["c", "m", "n", "ng", "t"]), ("oe", true, ["c", "m", "n", "ng", "t"]),
            ("y", true, []), ("uy", true, ["ch", "n", "nh", "p", "t"]), ("uê", true, ["ch", "n", "nh"]),
            ("yê", false, ["m", "n", "ng", "t"]), ("uâ", false, ["n", "ng", "t"]), ("uyê", false, ["n", "t"]),
        ]
        for nucleus in ["ai", "ao", "au", "ay", "âu", "ây", "eo", "êu", "ia", "iu", "oi", "ôi", "ơi", "ui", "ưi",
                        "ưu", "ua", "ưa", "uơ", "iêu", "yêu", "oai", "oay", "oao", "oeo", "uêu", "uôi", "ươi", "ươu",
                        "uây", "uya", "uyu"] {
            table.append((nucleus, true, []))
        }
        return table
    }()

    /// The spelling exceptions (spec §7.5): spelling, tone, onset letters, nucleus letters; the coda is the rest.
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
        ("kuăng", .none, 1, 2),  // kuăng
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

    /// The spelling exceptions, split by letter count rather than by the engine's tables.
    static let exceptions: [Syllable] = exceptionData.map { spelling, tone, onset, nucleus in
        let letters = Array(spelling)
        return Syllable(onset: String(letters[..<onset]), nucleus: String(letters[onset..<(onset + nucleus)]),
                        coda: String(letters[(onset + nucleus)...]), tone: tone)
    }

    /// Every valid syllable with the native onsets, plus the exceptions.
    static let all: [Syllable] = withExceptions(build(onsets: onsets), foreign: false)
    /// Valid syllables when `allowForeignConsonants` is on (Telex adds z f j; VNI also w).
    static let foreignTelex: [Syllable] = withExceptions(build(onsets: onsets + ["z", "f", "j"]), foreign: true)
    static let foreignVNI: [Syllable] = withExceptions(build(onsets: onsets + ["z", "f", "j", "w"]), foreign: true)

    /// Appends the exceptions whose letters and tone the list does not already hold. Entries whose onset holds
    /// `j` or `z` join only the foreign lists.
    private static func withExceptions(_ list: [Syllable], foreign: Bool) -> [Syllable] {
        let present = keySet(list)
        return list + exceptions.filter {
            (foreign || !$0.onset.contains(where: { $0 == "j" || $0 == "z" }))
                && !present.contains("\($0.letters)|\($0.tone.rawValue)")
        }
    }

    /// "letters|tone" keys of the valid syllables for the options, for independent validity checks.
    static func validKeys(for options: Options) -> Set<String> {
        if !options.allowForeignConsonants { return nativeKeys }
        return options.inputMethod == .vni ? foreignVNIKeys : foreignTelexKeys
    }

    private static let nativeKeys = keySet(all)
    private static let foreignTelexKeys = keySet(foreignTelex)
    private static let foreignVNIKeys = keySet(foreignVNI)

    private static func keySet(_ list: [Syllable]) -> Set<String> {
        Set(list.map { "\($0.letters)|\($0.tone.rawValue)" })
    }

    /// Every non-empty prefix of a valid syllable's letters, for independent "can still become a syllable" checks.
    static func prefixes(for options: Options) -> Set<String> {
        if !options.allowForeignConsonants { return nativePrefixes }
        return options.inputMethod == .vni ? foreignVNIPrefixes : foreignTelexPrefixes
    }

    private static let nativePrefixes = prefixSet(all)
    private static let foreignTelexPrefixes = prefixSet(foreignTelex)
    private static let foreignVNIPrefixes = prefixSet(foreignVNI)

    private static func prefixSet(_ list: [Syllable]) -> Set<String> {
        var result: Set<String> = []
        for syllable in list {
            let letters = Array(syllable.letters)
            for end in 1...letters.count { result.insert(String(letters[..<end])) }
        }
        return result
    }

    private static func build(onsets: [String]) -> [Syllable] {
        var result: [Syllable] = []
        for onset in onsets {
            for (nucleus, open, codas) in nuclei {
                if onset == "qu" && (nucleus.hasPrefix("u") || nucleus.hasPrefix("ư")) { continue }
                if onset == "gi" && nucleus.hasPrefix("i") { continue }
                // The engine parses g + ia/iu as gi + a/u (longest onset), so only that split is generated.
                if onset == "g" && (nucleus == "ia" || nucleus == "iu") { continue }
                if !spellingAllows(onset: onset, nucleus: nucleus) { continue }
                var allowed = codas
                if nucleus == "y" && onset == "qu" { allowed = ["n", "nh", "t"] }
                let codaChoices = (open ? [""] : []) + allowed
                for coda in codaChoices {
                    for tone in Tone.allCases {
                        let stop = ["c", "ch", "p", "t"].contains(coda)
                        if stop && (tone == .grave || tone == .hook || tone == .tilde) { continue }
                        result.append(Syllable(onset: onset, nucleus: nucleus, coda: coda, tone: tone))
                    }
                }
            }
        }
        return result
    }

    private static let labialOnsets: Set<String> = ["b", "m", "p", "ph", "v"]
    private static let glideNuclei: Set<String> = ["oa", "oă", "oe", "uâ", "uê", "uy", "uyê", "uya", "uyu", "oai", "oay",
                                                   "oao", "oeo", "uây"]

    /// Spec §7.1: R1 (c/k, g/gh, ng/ngh before the nucleus's first letter, `ê` as `e`), R2 (`yê`/`yêu` only with no
    /// onset or `qu`) and L1 (no rounded glide after a labial onset).
    private static func spellingAllows(onset: String, nucleus: String) -> Bool {
        let first = nucleus.first!
        let e = first == "e" || first == "ê"
        let i = first == "i"
        let y = first == "y"
        switch onset {
        case "c": if e || i || y { return false }
        case "k": if !(e || i || y) { return false }
        case "g": if e { return false }
        case "gh", "ngh": if !(e || i) { return false }
        case "ng": if e || i { return false }
        default: break
        }
        if (nucleus == "yê" || nucleus == "yêu") && !(onset.isEmpty || onset == "qu") { return false }
        if labialOnsets.contains(onset) && glideNuclei.contains(nucleus) { return false }
        return true
    }
}

private let toneMarks: [Tone: String] = [.acute: "\u{301}", .grave: "\u{300}", .hook: "\u{309}", .tilde: "\u{303}", .dot: "\u{323}"]
private let modifiedVowels: Set<Character> = ["ă", "â", "ê", "ô", "ơ", "ư"]

/// Puts a tone mark on `letters[index]` using Unicode composition, not the engine's tables.
func withTone(_ letters: String, tone: Tone, at index: Int?) -> String {
    guard let index, let mark = toneMarks[tone] else { return letters }
    var characters = Array(letters)
    characters[index] = Character((String(characters[index]) + mark).precomposedStringWithCanonicalMapping)
    return String(characters)
}

/// The text a syllable must display, with the tone placed by spec §8 rules written independently.
func expectedText(_ syllable: Syllable, style: ToneStyle) -> String {
    let start = syllable.onset.count
    let nucleus = Array(syllable.nucleus)
    var offset: Int
    if let modified = nucleus.lastIndex(where: { modifiedVowels.contains($0) }) {
        offset = modified
    } else if !syllable.coda.isEmpty {
        offset = nucleus.count - 1
    } else if nucleus.count == 3 {
        offset = 1
    } else if nucleus.count == 2 && ["oa", "oe", "uy"].contains(syllable.nucleus) {
        offset = style == .old ? 0 : 1
    } else {
        offset = 0
    }
    return withTone(syllable.letters, tone: syllable.tone, at: syllable.tone == .none ? nil : start + offset)
}

private let vowelLetters: Set<Character> = ["a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y"]

/// Prefixes of the oracle's syllables that carry the hook tone, for the Telex coda `r` escape.
private let hookPrefixes: Set<String> = {
    var result: Set<String> = []
    for syllable in Syllables.all where syllable.tone == .hook {
        let letters = Array(syllable.letters)
        for end in 1...letters.count { result.insert(String(letters[..<end])) }
    }
    return result
}()

/// Keys that type `letters` with `tone` (spec §10 layer 2), or nil when the form is given up for the method.
/// Telex types an open `uơ` after any onset but `th` with `[`; VNI cannot type it. Telex types the second `o` of
/// the `oo` nucleus as `oo`: the first turns `oo` into `ô`, the second undoes it. Likewise Telex types a coda `r`
/// as `rr` when the letters before it, with the hook tone, begin a syllable of `Syllables.all` (`dêr` → `deerr`):
/// the first `r` is the hook, the second undoes it (spec §7.5). Telex and Simple Telex cannot type `êê` or `ơơ`
/// (spec §7.5): the third key undoes the modifier.
func canonicalKeys(_ letters: String, tone: Tone, method: InputMethod) -> String? {
    if method != .vni {
        let lower = letters.lowercased()
        if lower.contains("êê") || lower.contains("ơơ") { return nil }
    }
    let characters = Array(letters)
    let doubledCodaR = method != .vni && characters.count >= 2
        && characters[characters.count - 1].lowercased() == "r"
        && vowelLetters.contains(Character(characters[characters.count - 2].lowercased()))
        && hookPrefixes.contains(String(characters.dropLast()).lowercased())
    var keys = ""
    for (index, character) in characters.enumerated() {
        let lower = Character(character.lowercased())
        let upper = character.isUppercase
        func base(_ b: Character) -> String { upper ? b.uppercased() : String(b) }
        let isOpenUO = lower == "ơ" && index > 0 && characters[index - 1].lowercased() == "u"
            && index == characters.count - 1
            && !(index >= 2 && characters[index - 2].lowercased() == "q")
            && !(index == 3 && letters.lowercased().hasPrefix("th"))
        switch (lower, method) {
        case ("o", _) where method != .vni && index > 0 && characters[index - 1].lowercased() == "o": keys += base("o") + base("o")
        case ("ơ", _) where method != .vni && isOpenUO: keys += upper ? "{" : "["
        case ("ơ", .vni) where isOpenUO: return nil
        case ("â", .telex), ("â", .simpleTelex): keys += base("a") + "a"
        case ("ê", .telex), ("ê", .simpleTelex): keys += base("e") + "e"
        case ("ô", .telex), ("ô", .simpleTelex): keys += base("o") + "o"
        case ("ă", .telex), ("ă", .simpleTelex): keys += base("a") + "w"
        case ("ơ", .telex), ("ơ", .simpleTelex): keys += base("o") + "w"
        case ("ư", .telex), ("ư", .simpleTelex): keys += base("u") + "w"
        case ("đ", .telex), ("đ", .simpleTelex): keys += base("d") + "d"
        case ("â", .vni): keys += base("a") + "6"
        case ("ê", .vni): keys += base("e") + "6"
        case ("ô", .vni): keys += base("o") + "6"
        case ("ă", .vni): keys += base("a") + "8"
        case ("ơ", .vni): keys += base("o") + "7"
        case ("ư", .vni): keys += base("u") + "7"
        case ("đ", .vni): keys += base("d") + "9"
        default:
            keys.append(character)
            if doubledCodaR && index == characters.count - 1 { keys.append(character) }
        }
    }
    let telexTones: [Tone: String] = [.acute: "s", .grave: "f", .hook: "r", .tilde: "x", .dot: "j"]
    let vniTones: [Tone: String] = [.acute: "1", .grave: "2", .hook: "3", .tilde: "4", .dot: "5"]
    keys += (method == .vni ? vniTones : telexTones)[tone] ?? ""
    return keys
}

/// Splits a toned word into untoned letters, its tone and the index of the toned letter.
func decompose(_ word: String) -> (letters: String, tone: Tone, toneIndex: Int?)? {
    let marks: [UInt32: Tone] = [0x301: .acute, 0x300: .grave, 0x309: .hook, 0x303: .tilde, 0x323: .dot]
    var letters = ""
    var tone = Tone.none
    var toneIndex: Int?
    for (index, character) in word.enumerated() {
        var kept = ""
        for scalar in String(character).decomposedStringWithCanonicalMapping.unicodeScalars {
            if let found = marks[scalar.value] {
                guard toneIndex == nil else { return nil }
                tone = found
                toneIndex = index
            } else {
                kept.unicodeScalars.append(scalar)
            }
        }
        letters += kept.precomposedStringWithCanonicalMapping
    }
    return (letters, tone, toneIndex)
}
