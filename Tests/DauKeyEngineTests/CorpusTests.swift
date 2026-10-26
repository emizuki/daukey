import Foundation
import Testing
@testable import DauKeyEngine

private let methodsAndStyles: [Options] = [
    Options(), Options(toneStyle: .modern), Options(inputMethod: .vni), Options(inputMethod: .vni, toneStyle: .modern),
]

@Suite struct CorpusTests {
    @Test(arguments: Options.all)
    func everyGeneratedSyllableTypesFromCanonicalKeys(_ options: Options) {
        var failures: [String] = []
        let syllables = options.allowForeignConsonants
            ? (options.inputMethod == .telex ? Syllables.foreignTelex : Syllables.foreignVNI)
            : Syllables.all
        for syllable in syllables {
            guard let keys = canonicalKeys(syllable.letters, tone: syllable.tone, method: options.inputMethod) else { continue }
            let expected = expectedText(syllable, style: options.toneStyle) + " "
            let actual = typed(keys + " ", options)
            if Array(actual.unicodeScalars) != Array(expected.unicodeScalars) {
                failures.append("\(keys) → \(actual) expected \(expected)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures, first: \(failures.prefix(20))")
    }

    @Test(arguments: methodsAndStyles)
    func toneKeyPositionDoesNotMatter(_ options: Options) {
        var failures: [String] = []
        for syllable in Syllables.all where syllable.tone != .none {
            guard let keys = canonicalKeys(syllable.letters, tone: .none, method: options.inputMethod),
                  let full = canonicalKeys(syllable.letters, tone: syllable.tone, method: options.inputMethod)
            else { continue }
            let toneKey = full.last!
            let expected = expectedText(syllable, style: options.toneStyle) + " "
            let base = Array(keys)
            // The onset's canonical keys come first (`đ` is "dd" or "d9").
            let onsetKeys = canonicalKeys(syllable.onset, tone: .none, method: options.inputMethod)?.count ?? 0
            let firstVowel = onsetKeys
            for position in (firstVowel + 1)...base.count {
                var moved = base
                moved.insert(toneKey, at: position)
                let actual = typed(String(moved) + " ", options)
                if Array(actual.unicodeScalars) != Array(expected.unicodeScalars) {
                    failures.append("\(String(moved)) → \(actual) expected \(expected)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures, first: \(failures.prefix(20))")
    }

    @Test(arguments: methodsAndStyles)
    func singleModifierKeyPositionDoesNotMatter(_ options: Options) {
        let modifiedVowels: Set<Character> = ["ă", "â", "ê", "ô", "ơ", "ư"]
        var failures: [String] = []
        // The `oo` nucleus has no modifier key: its repeated `o` keys are a circumflex and its undo.
        for syllable in Syllables.all
        where syllable.nucleus != "oo" && syllable.letters.filter({ modifiedVowels.contains($0) }).count <= 1 {
            guard let keys = canonicalKeys(syllable.letters, tone: syllable.tone, method: options.inputMethod) else { continue }
            let expected = expectedText(syllable, style: options.toneStyle) + " "
            let characters = Array(keys)
            let movable = characters.indices.filter { $0 > 0 && isModifierKey(characters[$0], after: characters[$0 - 1], options) }
            for index in movable {
                let key = characters[index]
                var without = characters
                without.remove(at: index)
                for position in index...without.count {
                    var moved = without
                    moved.insert(key, at: position)
                    let actual = typed(String(moved) + " ", options)
                    if Array(actual.unicodeScalars) != Array(expected.unicodeScalars) {
                        failures.append("\(String(moved)) → \(actual) expected \(expected)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures, first: \(failures.prefix(20))")
    }

    @Test(arguments: methodsAndStyles)
    func dictionarySyllables(_ options: Options) throws {
        let url = try #require(Bundle.module.url(forResource: "Viet74K", withExtension: "txt", subdirectory: "Fixtures"))
        let rejectsURL = try #require(Bundle.module.url(forResource: "rejects", withExtension: "tsv", subdirectory: "Fixtures"))
        let reasons: Set<String> = ["foreign onset", "given-up form", "non-Vietnamese spelling", "proper noun spelling", "dictionary error"]
        var rejects = Set<String>()
        for line in try String(contentsOf: rejectsURL, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t").map(String.init)
            #expect(fields.count == 2 && reasons.contains(fields[1]), "bad reject line: \(line)")
            if let entry = fields.first { rejects.insert(entry) }
        }
        // Tokens made only of Vietnamese letters (any tone marks allowed), including malformed ones, so that every
        // failure is either fixed or rejected with a reason.
        let bases = Set("abcdefghijklmnopqrstuvwxyzđ".unicodeScalars)
        var tokens = Set<String>()
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            for token in line.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }) {
                let word = String(token)
                let isLetters = word.allSatisfy { character in
                    String(character).decomposedStringWithCanonicalMapping.unicodeScalars.first.map(bases.contains) ?? false
                }
                if isLetters { tokens.insert(word) }
            }
        }
        #expect(rejects.subtracting(tokens).isEmpty, "reject entries not in the dictionary: \(rejects.subtracting(tokens).prefix(20))")
        let valid = Syllables.validKeys(for: options)
        var failures: [String] = []
        var unexpectedPasses: [String] = []
        for word in tokens.sorted() {
            guard let parts = decompose(word) else {
                if !rejects.contains(word) { failures.append("\(word)\t(more than one tone)") }
                continue
            }
            // VNI cannot type an open uơ (spec §9.1, given up).
            guard let keys = canonicalKeys(parts.letters, tone: parts.tone, method: options.inputMethod) else { continue }
            var expected = word
            if let index = parts.toneIndex, let pairStart = openPairStart(parts.letters) {
                expected = withTone(parts.letters, tone: parts.tone, at: options.toneStyle == .old ? pairStart : pairStart + 1)
                #expect(index == pairStart || index == pairStart + 1, "dictionary tone outside the pair in \(word)")
            }
            let actual = typed(keys + " ", options)
            let isValid = valid.contains("\(parts.letters)|\(parts.tone.rawValue)")
            let passes = isValid && Array(actual.unicodeScalars) == Array((expected + " ").unicodeScalars)
            if !passes && !rejects.contains(word) { failures.append("\(word)\t\(keys) → \(actual)") }
            if passes && rejects.contains(word) { unexpectedPasses.append(word) }
        }
        #expect(failures.isEmpty, "\(failures.count) unreviewed failures:\n\(failures.joined(separator: "\n"))")
        // A reject may pass in one method and fail in the other (for example VNI cannot type open uơ), so this is informational.
        if !unexpectedPasses.isEmpty { print("rejects passing with \(options): \(unexpectedPasses.prefix(50))") }
    }
}

/// True for the key that adds the modifier to the letter typed just before it, or for the `[` that types the
/// final `ơ` of an open `uơ` (`canonicalKeys`).
private func isModifierKey(_ key: Character, after previous: Character, _ options: Options) -> Bool {
    switch options.inputMethod {
    case .telex:
        let lower = key.lowercased(), before = previous.lowercased()
        return lower == "w" || lower == "[" || (lower == before && "aeod".contains(lower))
    case .vni:
        return "6789".contains(key)
    }
}

/// Start index of a final open `oa`, `oe` or `uy` nucleus (not the `uy` of `quy`), else nil.
private func openPairStart(_ letters: String) -> Int? {
    let characters = Array(letters)
    guard characters.count >= 2 else { return nil }
    let pair = String(characters.suffix(2))
    guard ["oa", "oe", "uy"].contains(pair) else { return nil }
    let start = characters.count - 2
    if start > 0 && "aeiouyăâêôơư".contains(characters[start - 1]) { return nil }
    if pair == "uy" && start > 0 && characters[start - 1] == "q" { return nil }
    return start
}
