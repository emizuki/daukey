import DauKeyEngine
import DauKeyHook

enum Command: Sendable {
    case start, checkTap
    case setEnabled(Bool), setOptions(Options)
    case setPerAppSwitching(Bool), setSoundEnabled(Bool), setShortcut(ShortcutConfig)
    case resetToDefaults
    case appActivated(String?, inlineCompletionApp: Bool), inputSourceChanged, reset
}

func drainCommands(_ commands: AsyncStream<Command>, into typist: Typist) async {
    for await command in commands { await typist.handle(command) }
}
