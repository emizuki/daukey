import Foundation
import CoreFoundation

class RunLoopExecutor: SerialExecutor, @unchecked Sendable {
    let runLoop: CFRunLoop
    let thread: Thread
    init(runLoop: CFRunLoop, thread: Thread) {
        self.runLoop = runLoop
        self.thread = thread
    }
    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        perform(jobBlock(job, executor: asUnownedSerialExecutor()))
    }
    func perform(_ block: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
    func checkIsolated() {
        precondition(Thread.current === thread, "Typing state accessed off the typing thread")
    }
}
private func jobBlock(_ job: UnownedJob, executor: UnownedSerialExecutor) -> @Sendable () -> Void {
    { job.runSynchronously(on: executor) }
}
