/// A macro: a typed token that is replaced by `replacement` when the token ends.
public struct MacroRule: Sendable, Equatable {
    public var trigger: String
    public var replacement: String

    public init(trigger: String, replacement: String) {
        self.trigger = trigger
        self.replacement = replacement
    }
}

/// Macro and exclusion lookups compiled from rule rows.
///
/// Immutable; a session keeps the tables a token started with, and copies share storage.
public struct RuleTables: Sendable, Equatable {
    private let replacements: [String: String]
    private let excluded: Set<String>
    /// Characters in the longest trigger key; a longer token never matches.
    let maxTriggerLength: Int

    /// Rows without a trigger or a replacement, and triggers or exclusions containing whitespace, are left out
    /// without changing the rows themselves. When several macros share a key, the last one wins. Replacements are
    /// kept verbatim.
    public init(macros: [MacroRule] = [], exclusions: [String] = []) {
        var replacements: [String: String] = [:]
        for macro in macros where Self.isUsable(macro.trigger) && !macro.replacement.isEmpty {
            replacements[Self.key(macro.trigger)] = macro.replacement
        }
        self.replacements = replacements
        excluded = Set(exclusions.lazy.filter(Self.isUsable).map(Self.key))
        maxTriggerLength = replacements.keys.lazy.map(\.count).max() ?? 0
    }

    /// The key a trigger, an exclusion, or typed text is matched by: lowercased, then compared as a Swift `String`,
    /// so canonically equivalent text matches; there is no other case folding.
    public static func key(_ text: String) -> String {
        text.lowercased()
    }

    /// The replacement for a token showing `token`, if a macro matches it.
    public func replacement(for token: String) -> String? {
        replacements[Self.key(token)]
    }

    /// Whether `rawWord`, a word as typed, is left as typed when it ends.
    public func excludes(_ rawWord: String) -> Bool {
        !excluded.isEmpty && excluded.contains(Self.key(rawWord))
    }

    private static func isUsable(_ trigger: String) -> Bool {
        !trigger.isEmpty && !trigger.contains(where: \.isWhitespace)
    }
}
