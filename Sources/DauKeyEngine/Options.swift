/// Keyboard convention used to type Vietnamese marks.
public enum InputMethod: String, Sendable, Equatable, CaseIterable {
    case telex
    case simpleTelex
    case vni
}

/// Where the tone goes in open `oa`, `oe` and `uy` syllables.
public enum ToneStyle: Sendable, Equatable, CaseIterable {
    /// hòa, hòe, thủy
    case old
    /// hoà, hoè, thuỷ
    case modern
}

/// How strictly words are checked against Vietnamese spelling.
public enum Spelling: Sendable, Equatable, CaseIterable {
    case off
    case check
    case checkAndRestore
}

public struct Options: Equatable, Sendable {
    public var inputMethod: InputMethod
    public var toneStyle: ToneStyle
    public var spelling: Spelling
    public var allowForeignConsonants: Bool

    public init(
        inputMethod: InputMethod = .telex,
        toneStyle: ToneStyle = .old,
        spelling: Spelling = .checkAndRestore,
        allowForeignConsonants: Bool = false
    ) {
        self.inputMethod = inputMethod
        self.toneStyle = toneStyle
        self.spelling = spelling
        self.allowForeignConsonants = allowForeignConsonants
    }
}
