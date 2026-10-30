import AppKit
import DauKeyHook
import Observation

/// Records a new V/E shortcut through the typing core, which owns the capture and sees the physical keys.
///
/// Each recording has a new ID. Capture snapshots carrying another ID are ignored, so a late acknowledgment or result
/// of an earlier recording can neither arm, fire nor cancel the current one. The core keeps a recorded chord in every
/// snapshot until the matching end, so the result arrives even when the phases before it were coalesced. While the
/// core captures, a local monitor keeps key events from acting on the app's own controls; it does not decide the chord.
@MainActor @Observable final class ShortcutRecorder {
    /// The recording waiting for its result; nil when not recording.
    private(set) var activeID: UInt64?
    @ObservationIgnored private let commands: AsyncStream<Command>.Continuation
    @ObservationIgnored private var lastID: UInt64 = 0
    @ObservationIgnored private var onRecord: ((ShortcutConfig) -> Void)?
    @ObservationIgnored private var monitor: Any?

    init(commands: AsyncStream<Command>.Continuation) {
        self.commands = commands
    }

    var isRecording: Bool { activeID != nil }

    /// Whether the local monitor that keeps keys from the app's controls is installed.
    var hasMonitor: Bool { monitor != nil }

    /// Starts a new recording, ending the current one first; `onRecord` is called once with the chord.
    func start(onRecord: @escaping (ShortcutConfig) -> Void) {
        stop()
        let (next, overflow) = lastID.addingReportingOverflow(1)
        precondition(!overflow, "Shortcut recording IDs are exhausted")
        lastID = next
        activeID = next
        self.onRecord = onRecord
        commands.yield(.beginShortcutCapture(id: next))
    }

    /// Follows the core's capture for the current recording.
    func update(_ capture: CaptureSnapshot) {
        guard let id = activeID, capture.id == id else { return }
        switch capture.phase {
        case .waitingForRelease, .recording:
            installMonitor()
        case .recorded(let config):
            // Disarmed before the callback, which may start another recording.
            let callback = onRecord
            disarm()
            callback?(config)
            commands.yield(.endShortcutCapture(id: id))
        case .inactive:
            disarm()
        }
    }

    /// Ends the current recording at once; a result that arrives later is ignored.
    func stop() {
        guard let id = activeID else { return }
        disarm()
        commands.yield(.endShortcutCapture(id: id))
    }

    private func disarm() {
        activeID = nil
        onRecord = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { _ in nil }
    }
}
