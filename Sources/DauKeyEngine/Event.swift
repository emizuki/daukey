public enum Event: Equatable, Sendable {
    /// The character a key produces, with Shift and Caps Lock applied. Return is "\n", Tab is "\t".
    case char(Character)
    case backspace
    /// A key that ends the word without producing text: cursor keys, forward delete, Escape, shortcuts.
    case endWord
    /// The cursor position is unknown: mouse click, app switch, focus change.
    case reset
}

public enum Action: Equatable, Sendable {
    /// Nothing to change; the original key, if any, goes through.
    case passThrough
    /// Swallow the original key, send `deleteCount` backspaces, then type `insert`.
    case replace(deleteCount: Int, insert: String)
    /// Send `deleteCount` backspaces, type `insert`, then deliver the original key.
    case replaceThenPass(deleteCount: Int, insert: String)
}
