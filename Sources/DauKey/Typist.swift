import DauKeyEngine
import DauKeyHook

actor Typist {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    private var core: TypingCore
    private let snapshots: AsyncStream<Snapshot>.Continuation
    private var lastSnapshot: Snapshot?
    init(executor: RunLoopExecutor, enabled: Bool, options: Options, appMemory: [String: Bool],
         snapshots: AsyncStream<Snapshot>.Continuation) {
        self.executor = executor
        core = TypingCore(enabled: enabled, options: options, appMemory: appMemory)
        self.snapshots = snapshots
    }
    func handle(_ command: Command) {
        switch command {
        case .setEnabled(let enabled): core.setEnabled(enabled)
        case .setOptions(let options): core.setOptions(options)
        case .appActivated(let id): core.appActivated(id)
        case .inputSourceChanged: core.inputSourceChanged()
        case .reset: core.reset()
        }
        publishSnapshot()
    }
    func publishSnapshot() {
        let snapshot = core.snapshot
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        snapshots.yield(snapshot)
    }
}
