import Foundation
import CoreFoundation

final class TypingThread: Sendable {
    let executor: RunLoopExecutor
    init() {
        let publication = RunLoopPublication()
        let thread = Thread {
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let keepalive = CFRunLoopSourceCreate(nil, 0, &context)!
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, keepalive, .commonModes)
            publication.executor = RunLoopExecutor(runLoop: loop, thread: Thread.current)
            publication.ready.signal()
            CFRunLoopRun()
            withExtendedLifetime(keepalive) {}
        }
        thread.name = "DauKey typing"
        thread.start()
        publication.ready.wait()
        executor = publication.executor!
    }
}
// Publication is written once, then read only after the semaphore handoff.
private final class RunLoopPublication: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    var executor: RunLoopExecutor?
}
