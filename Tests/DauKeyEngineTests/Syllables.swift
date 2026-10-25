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
            ("ê", true, front), ("i", true, front), ("ơ", true, ["m", "n", "p", "t"]),
            ("ư", true, ["c", "m", "n", "ng", "t"]), ("uô", false, ["c", "m", "n", "ng", "t"]),
            ("oă", false, ["c", "m", "n", "ng", "t"]), ("oe", true, ["c", "m", "n", "ng", "t"]),
            ("y", true, ["t"]), ("uy", true, ["ch", "n", "nh", "p", "t"]), ("uê", true, ["ch", "n", "nh"]),
            ("yê", false, ["m", "n", "ng", "t"]), ("uâ", false, ["n", "ng", "t"]), ("uyê", false, ["n", "t"]),
        ]
        for nucleus in ["ai", "ao", "au", "ay", "âu", "ây", "eo", "êu", "ia", "iu", "oi", "ôi", "ơi", "ui", "ưi",
                        "ưu", "ua", "ưa", "uơ", "iêu", "yêu", "oai", "oay", "oao", "oeo", "uôi", "ươi", "ươu",
                        "uây", "uya", "uyu"] {
            table.append((nucleus, true, []))
        }
        return table
    }()

    /// Every valid syllable with the native onsets.
    static let all: [Syllable] = build(onsets: onsets)
    /// Valid syllables when `allowForeignConsonants` is on (Telex adds z f j; VNI also w).
    static let foreignTelex: [Syllable] = build(onsets: onsets + ["z", "f", "j"])
    static let foreignVNI: [Syllable] = build(onsets: onsets + ["z", "f", "j", "w"])

    /// "letters|tone" keys of the valid syllables for the options, for independent validity checks.
    static func validKeys(for options: Options) -> Set<String> {
        if !options.allowForeignConsonants { return nativeKeys }
        return options.inputMethod == .telex ? foreignTelexKeys : foreignVNIKeys
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
        return options.inputMethod == .telex ? foreignTelexPrefixes : foreignVNIPrefixes
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

/// Keys that type `letters` with `tone` (spec §10 layer 2), or nil when the form is given up for the method.
/// Telex types an open `uơ` after any onset but `th` with `[`; VNI cannot type it.
func canonicalKeys(_ letters: String, tone: Tone, method: InputMethod) -> String? {
    let characters = Array(letters)
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
        case ("ơ", .telex) where isOpenUO: keys += upper ? "{" : "["
        case ("ơ", .vni) where isOpenUO: return nil
        case ("â", .telex): keys += base("a") + "a"
        case ("ê", .telex): keys += base("e") + "e"
        case ("ô", .telex): keys += base("o") + "o"
        case ("ă", .telex): keys += base("a") + "w"
        case ("ơ", .telex): keys += base("o") + "w"
        case ("ư", .telex): keys += base("u") + "w"
        case ("đ", .telex): keys += base("d") + "d"
        case ("â", .vni): keys += base("a") + "6"
        case ("ê", .vni): keys += base("e") + "6"
        case ("ô", .vni): keys += base("o") + "6"
        case ("ă", .vni): keys += base("a") + "8"
        case ("ơ", .vni): keys += base("o") + "7"
        case ("ư", .vni): keys += base("u") + "7"
        case ("đ", .vni): keys += base("d") + "9"
        default: keys.append(character)
        }
    }
    let telexTones: [Tone: String] = [.acute: "s", .grave: "f", .hook: "r", .tilde: "x", .dot: "j"]
    let vniTones: [Tone: String] = [.acute: "1", .grave: "2", .hook: "3", .tilde: "4", .dot: "5"]
    keys += (method == .telex ? telexTones : vniTones)[tone] ?? ""
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
