import DauKeyEngine

// Tap lifecycle commands are added with the macOS hook.
enum Command: Sendable {
    case setEnabled(Bool), setOptions(Options)
    case appActivated(String?), inputSourceChanged, reset
}

func drainCommands(_ commands: AsyncStream<Command>, into typist: Typist) async {
    for await command in commands { await typist.handle(command) }
}
