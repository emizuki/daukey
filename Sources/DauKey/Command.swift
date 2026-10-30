import DauKeyEngine
import DauKeyHook

/// Requests to the typing runtime, applied in order on the typing thread.
enum Command: Sendable, Equatable {
    case start, checkTap
    case settings(SettingsChange)
    case replaceRules(RuleTables)
    case resetToDefaults
    case beginShortcutCapture(id: UInt64)
    case endShortcutCapture(id: UInt64)
    case context(ContextObservation)
    case appActivated(bundleID: String?, processID: Int32?, inlineCompletionApp: Bool)
    case inputSourceChanged, reset
}

func drainCommands(_ commands: AsyncStream<Command>, into typist: Typist) async {
    for await command in commands { await typist.handle(command) }
}

extension TypingCore {
    /// Applies a command that only changes core state; nil for `start` and `checkTap`, which the Typist handles.
    mutating func handle(_ command: Command) -> RuntimeResult? {
        switch command {
        case .start, .checkTap:
            return nil
        case .settings(let change):
            return apply(change)
        case .replaceRules(let rules):
            replaceRules(rules)
        case .resetToDefaults:
            return resetToDefaults()
        case .beginShortcutCapture(let id):
            beginShortcutCapture(id: id)
        case .endShortcutCapture(let id):
            endShortcutCapture(id: id)
        case .context(let observation):
            handleContext(observation)
        case .appActivated(let bundleID, let processID, let inlineCompletionApp):
            return appActivated(bundleID, processID: processID, inlineCompletionApp: inlineCompletionApp)
        case .inputSourceChanged:
            inputSourceChanged()
        case .reset:
            reset()
        }
        return nil
    }
}
