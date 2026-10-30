import Testing
import DauKeyHook

private let control: Modifiers = .control
private let controlShift: Modifiers = [.control, .shift]
private let keyK: UInt16 = 0x28
private let keyJ: UInt16 = 0x26
private let keyA: UInt16 = 0x00
private let escape: UInt16 = 0x35
private let f5: UInt16 = 0x60

private func down(_ keyCode: UInt16, _ modifiers: Modifiers = [], isRepeat: Bool = false) -> ShortcutEvent {
    .keyDown(KeyInput(keyCode: keyCode, modifiers: modifiers, characters: "", isRepeat: isRepeat))
}

/// Feeds `events` and returns the phase after each one.
private func phases(_ capture: inout ShortcutCapture, _ events: [ShortcutEvent]) -> [CapturePhase] {
    events.map { event in
        capture.handle(event)
        return capture.phase
    }
}

@Suite struct ShortcutCaptureTests {
    @Test func snapshotBootstrapsWithoutSessionAndInactive() {
        let snapshot = CaptureSnapshot()
        #expect(snapshot.id == nil)
        #expect(snapshot.phase == .inactive)
        #expect(CaptureSnapshot(id: 7, phase: .recording) == CaptureSnapshot(id: 7, phase: .recording))
    }

    @Test func recordsImmediatelyWhenNothingIsHeld() {
        let capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        #expect(capture.phase == .recording)
        let capsLockOnly = ShortcutCapture(heldModifiers: .capsLock, heldKeys: [])
        #expect(capsLockOnly.phase == .recording)
    }

    /// Keys held when capture starts must be released first; their chord never becomes a result.
    @Test func heldInputsMustBeReleasedBeforeRecording() {
        var capture = ShortcutCapture(heldModifiers: controlShift, heldKeys: [keyK])
        #expect(capture.phase == .waitingForRelease)
        let waiting = phases(&capture, [
            down(keyK, controlShift, isRepeat: true), .flagsChanged(control), down(keyJ, control), .keyUp(keyJ),
            .flagsChanged([]), .keyUp(keyK),
        ])
        #expect(waiting == [
            .waitingForRelease, .waitingForRelease, .waitingForRelease, .waitingForRelease,
            .waitingForRelease, .recording,
        ])
    }

    @Test func captureResultRemainsUntilAcknowledged() {
        var capture = ShortcutCapture(heldModifiers: control, heldKeys: [])
        #expect(capture.phase == .waitingForRelease)
        #expect(phases(&capture, [.flagsChanged(controlShift), .flagsChanged([])]) == [.waitingForRelease, .recording])

        let chord = phases(&capture, [
            .flagsChanged(control), down(keyK, control), down(keyK, control, isRepeat: true), .keyUp(keyK),
        ])
        #expect(chord == [.recording, .recording, .recording, .recording])
        let recorded = CapturePhase.recorded(ShortcutConfig(modifiers: control, keyCode: keyK))
        #expect(phases(&capture, [.flagsChanged([])]) == [recorded])

        let later = phases(&capture, [
            .flagsChanged(controlShift), down(keyJ, controlShift), down(keyJ, controlShift, isRepeat: true),
            .keyUp(keyJ), .flagsChanged([]), down(escape), .keyUp(escape),
        ])
        #expect(later == Array(repeating: recorded, count: 7))

        capture.cancel()
        #expect(capture.phase == .inactive)
    }

    /// A three-modifier chord is not recorded early when the second modifier goes down.
    @Test func threeModifierChordRecordsOnCompleteRelease() {
        var capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        let result = phases(&capture, [
            .flagsChanged(control), .flagsChanged(controlShift), .flagsChanged([.control, .shift, .option]),
            .flagsChanged(controlShift), .flagsChanged(.shift), .flagsChanged([]),
        ])
        #expect(result == [
            .recording, .recording, .recording, .recording, .recording,
            .recorded(ShortcutConfig(modifiers: [.control, .shift, .option], keyCode: nil)),
        ])
    }

    @Test func modifierKeyRecordsAfterCompleteReleaseInEitherOrder() {
        let expected = CapturePhase.recorded(ShortcutConfig(modifiers: controlShift, keyCode: keyK))

        var keyFirst = ShortcutCapture(heldModifiers: [], heldKeys: [])
        #expect(phases(&keyFirst, [
            .flagsChanged(controlShift), down(keyK, controlShift), .keyUp(keyK), .flagsChanged(control), .flagsChanged([]),
        ]) == [.recording, .recording, .recording, .recording, expected])

        var modifiersFirst = ShortcutCapture(heldModifiers: [], heldKeys: [])
        #expect(phases(&modifiersFirst, [
            .flagsChanged(controlShift), down(keyK, controlShift), .flagsChanged([]), .keyUp(keyK),
        ]) == [.recording, .recording, .recording, expected])
    }

    /// The key records with the modifiers it went down with, which the detector matches exactly.
    @Test func recordedKeyChordDrivesDetector() {
        let mods: Modifiers = [.control, .function]
        var capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        _ = phases(&capture, [.flagsChanged(control), down(f5, mods), .keyUp(f5), .flagsChanged([])])
        guard case .recorded(let config) = capture.phase else {
            Issue.record("expected a result, got \(capture.phase)")
            return
        }
        #expect(config == ShortcutConfig(modifiers: mods, keyCode: f5))
        var detector = ShortcutDetector(config: config)
        #expect(detector.handle(down(f5, mods)) == ShortcutDecision(toggle: true, consume: true))
    }

    @Test func capsLockIsNotPartOfChord() {
        var capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        let result = phases(&capture, [
            .flagsChanged(.capsLock), .flagsChanged(controlShift.union(.capsLock)), .flagsChanged(.capsLock),
        ])
        #expect(result == [.recording, .recording, .recorded(ShortcutConfig(modifiers: controlShift, keyCode: nil))])
    }

    /// Chords that cannot be a shortcut are dropped and recording continues.
    @Test func unusableChordsKeepRecording() {
        var capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        let unusable = phases(&capture, [
            .flagsChanged(control), .flagsChanged([]),
            .flagsChanged(.function), .flagsChanged([.function, .shift]), .flagsChanged([]),
            down(keyA), .keyUp(keyA),
            down(keyK, .function), .keyUp(keyK),
            .flagsChanged(control), down(keyK, control), down(keyJ, control), .keyUp(keyJ), .keyUp(keyK),
            .flagsChanged([]),
            down(keyK), .flagsChanged(control), .keyUp(keyK), .flagsChanged([]),
        ])
        #expect(unusable == Array(repeating: .recording, count: 19))
        #expect(phases(&capture, [.flagsChanged(controlShift), .flagsChanged([])])
                == [.recording, .recorded(ShortcutConfig(modifiers: controlShift, keyCode: nil))])
    }

    /// Shift alone with a key types a character, so a modifier+key chord needs Control, Option or Command.
    @Test func shiftAloneDoesNotMakeAKeyChord() {
        var capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        let shiftOnly = phases(&capture, [
            .flagsChanged(.shift), down(keyA, .shift), .keyUp(keyA), .flagsChanged([]),
            .flagsChanged(.shift), down(f5, [.shift, .function]), .keyUp(f5), .flagsChanged([]),
        ])
        #expect(shiftOnly == Array(repeating: .recording, count: 8))
        #expect(phases(&capture, [
            .flagsChanged(controlShift), down(keyA, controlShift), .keyUp(keyA), .flagsChanged([]),
        ]) == [.recording, .recording, .recording, .recorded(ShortcutConfig(modifiers: controlShift, keyCode: keyA))])
    }

    @Test func escapeCancelsWithoutChord() {
        var recording = ShortcutCapture(heldModifiers: [], heldKeys: [])
        #expect(phases(&recording, [.flagsChanged(controlShift), down(escape, controlShift), .flagsChanged([])])
                == [.recording, .inactive, .inactive])

        var waiting = ShortcutCapture(heldModifiers: control, heldKeys: [])
        #expect(phases(&waiting, [down(escape, control), .keyUp(escape), .flagsChanged([])])
                == [.inactive, .inactive, .inactive])
    }

    /// Losing focus cancels through `cancel()`; the half-pressed chord does not record afterwards.
    @Test func focusCancellationProducesNoChord() {
        var capture = ShortcutCapture(heldModifiers: [], heldKeys: [])
        _ = phases(&capture, [.flagsChanged(controlShift), down(keyK, controlShift)])
        capture.cancel()
        #expect(capture.phase == .inactive)
        #expect(phases(&capture, [.keyUp(keyK), .flagsChanged([]), .flagsChanged(controlShift), .flagsChanged([])])
                == [.inactive, .inactive, .inactive, .inactive])
    }
}
