import DauKeyEngine

public struct KeyInput: Sendable {
    public let keyCode: UInt16
    public let modifiers: Modifiers
    public let characters: String
    /// Whether this key-down is an autorepeat of a key that is still held.
    public let isRepeat: Bool
    public init(keyCode: UInt16, modifiers: Modifiers, characters: String, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.isRepeat = isRepeat
    }
}
public enum OutputStep: Equatable, Sendable {
    case backspaces(Int), selectBackward(Int), text(String)
}
public enum Decision: Equatable, Sendable {
    case pass, swallow([OutputStep]), passAfter([OutputStep])
}
/// What the core decided for one event or command.
public struct RuntimeResult: Equatable, Sendable {
    public let decision: Decision
    /// V/E actually changed; the Typist plays the feedback sound for it when sound is on.
    public let modeChanged: Bool
    /// The event changes text, so the core holds one receipt until the sender reports `commitSent` or `sendFailed`.
    public let requiresCommit: Bool

    public init(decision: Decision, modeChanged: Bool, requiresCommit: Bool = false) {
        self.decision = decision
        self.modeChanged = modeChanged
        self.requiresCommit = requiresCommit
    }
}
/// The runtime state the app shows and saves; it holds no typed text, text context or rules.
public struct Snapshot: Equatable, Sendable {
    public let enabled: Bool
    public let settings: TypingSettings
    public let appMemory: [String: Bool]
    public let tap: TapState
    public let shortcutCapture: CaptureSnapshot

    public init(
        enabled: Bool, settings: TypingSettings, appMemory: [String: Bool], tap: TapState,
        shortcutCapture: CaptureSnapshot = CaptureSnapshot()
    ) {
        self.enabled = enabled
        self.settings = settings
        self.appMemory = appMemory
        self.tap = tap
        self.shortcutCapture = shortcutCapture
    }
}
public enum TapState: Equatable, Sendable {
    case starting, running, noPermission, unavailable
}
