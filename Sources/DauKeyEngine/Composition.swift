/// One element of a composition and the keys that produced it (spec §6.1).
struct Slot: Equatable, Sendable {
    var element: Element
    /// Keys that created the element: its own key, or an undo key together with the keys it cancelled.
    var own: [Int]
    /// Keys whose modifier currently applies to the letter.
    var mods: [Int] = []
}

/// A closed segment of a word (spec §5.9). Its letters, tone and tone group no longer change.
struct Segment: Equatable, Sendable {
    var slots: [Slot]
    var tone: Tone
    var toneKeys: [Int]
    var toneAnchor: Int?
}

/// The working word `W` of spec §5: closed segments, then the current segment, which the fields below describe.
struct Composition: Equatable, Sendable {
    /// Closed segments, left to right.
    var earlier: [Segment] = []
    /// A stroke has applied in the word and no undo has happened since (spec §5.9).
    var spellingOffByStroke = false
    /// The last key applied a mid-word stroke, whose letter starts a new segment.
    var midWordStroke = false
    var slots: [Slot] = []
    var tone: Tone = .none
    /// Lowercased keys that undid their own effect and now only append.
    var escaped: Set<Character> = []
    /// The tone group `T`.
    var toneKeys: [Int] = []
    /// Where `T` stays while the tone is none after a remove-tone key.
    var toneAnchor: Int? = nil
    /// The last key was a Telex bracket that resolved to a break character and was not added.
    var lastKeyBroke = false

    var elements: [Element] { slots.map(\.element) }

    func letter(_ position: Int) -> Letter? {
        position >= 0 && position < slots.count ? slots[position].element.letter : nil
    }

    /// The slots of every segment, left to right.
    var allSlots: [Slot] { earlier.flatMap(\.slots) + slots }
}

enum Transform: Sendable {
    case tone(Tone)
    case removeTone
    case circumflex(Set<UInt8>)
    case hornBreve(horn: Bool, breve: Bool)
    case stroke
    case bracket(base: UInt8, uppercase: Bool)

    static func lookup(_ key: Character, _ method: InputMethod) -> Transform? {
        switch method {
        case .telex:
            switch key {
            case "s": return .tone(.acute)
            case "f": return .tone(.grave)
            case "r": return .tone(.hook)
            case "x": return .tone(.tilde)
            case "j": return .tone(.dot)
            case "z": return .removeTone
            case "a": return .circumflex([ASCII.a])
            case "e": return .circumflex([ASCII.e])
            case "o": return .circumflex([ASCII.o])
            case "w": return .hornBreve(horn: true, breve: true)
            case "d": return .stroke
            case "[": return .bracket(base: ASCII.o, uppercase: false)
            case "]": return .bracket(base: ASCII.u, uppercase: false)
            case "{": return .bracket(base: ASCII.o, uppercase: true)
            case "}": return .bracket(base: ASCII.u, uppercase: true)
            default: return nil
            }
        case .vni:
            switch key {
            case "1": return .tone(.acute)
            case "2": return .tone(.grave)
            case "3": return .tone(.hook)
            case "4": return .tone(.tilde)
            case "5": return .tone(.dot)
            case "0": return .removeTone
            case "6": return .circumflex([ASCII.a, ASCII.e, ASCII.o])
            case "7": return .hornBreve(horn: true, breve: false)
            case "8": return .hornBreve(horn: false, breve: true)
            case "9": return .stroke
            default: return nil
            }
        }
    }
}
