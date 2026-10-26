import Foundation
import CoreFoundation
import Testing
@testable import DauKey

actor ExecutorProbe {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    var values: [Int] = []
    init(_ executor: RunLoopExecutor) { self.executor = executor }
    func append(_ value: Int) {
        #expect(Thread.current === executor.thread)
        values.append(value)
    }
    func result() -> [Int] { values }
}
private final class QueuedExecutor: RunLoopExecutor, @unchecked Sendable {
    let queued = DispatchSemaphore(value: 0)
    override func enqueue(_ job: consuming ExecutorJob) {
        super.enqueue(job)
        queued.signal()
    }
}
private final class PausedLoop: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    let run = DispatchSemaphore(value: 0)
    var executor: QueuedExecutor!
    init() {
        let thread = Thread { [self] in
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let source = CFRunLoopSourceCreate(nil, 0, &context)!
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            executor = QueuedExecutor(runLoop: loop, thread: Thread.current)
            ready.signal()
            run.wait()
            CFRunLoopRun()
            withExtendedLifetime(source) {}
        }
        thread.start()
        ready.wait()
    }
}
@Suite(.timeLimit(.minutes(1))) struct RunLoopExecutorTests {
    @Test func actorJobsRunOnTypingThreadInProducerOrder() async {
        let typing = TypingThread()
        let probe = ExecutorProbe(typing.executor)
        for index in 0..<100 { await probe.append(index) }
        #expect(await probe.result() == Array(0..<100))
    }
    @Test func enqueuedJobSurvivesBeforeRunLoopStarts() async {
        let paused = PausedLoop()
        let probe = ExecutorProbe(paused.executor)
        let task = Task { await probe.append(42) }
        waitForJob(paused.executor)
        paused.run.signal()
        await task.value
        #expect(await probe.result() == [42])
        paused.executor.perform { CFRunLoopStop(paused.executor.runLoop) }
    }
    @Test func assumeIsolatedSucceedsOnTypingThread() async {
        let typing = TypingThread()
        let probe = ExecutorProbe(typing.executor)
        let result = AsyncStream<[Int]>.makeStream()
        typing.executor.perform {
            probe.assumeIsolated { isolated in
                isolated.append(42)
                result.continuation.yield(isolated.result())
                result.continuation.finish()
            }
        }
        var received: [[Int]] = []
        for await value in result.stream { received.append(value) }
        #expect(received == [[42]])
    }
    @Test func assumeIsolatedFailsOffTypingThread() async {
        await #expect(processExitsWith: .failure) {
            assumeIsolatedOffTypingThread()
        }
    }
}

private func waitForJob(_ executor: QueuedExecutor) { executor.queued.wait() }

private func assumeIsolatedOffTypingThread() {
    let typing = TypingThread()
    let probe = ExecutorProbe(typing.executor)
    probe.assumeIsolated { _ in }
}
