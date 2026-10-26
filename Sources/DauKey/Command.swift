import DauKeyEngine

enum Command: Sendable {
    case start, checkTap
    case setEnabled(Bool), setOptions(Options)
    case appActivated(String?, inlineCompletionApp: Bool), inputSourceChanged, reset
}

func drainCommands(_ commands: AsyncStream<Command>, into typist: Typist) async {
    for await command in commands { await typist.handle(command) }
}
