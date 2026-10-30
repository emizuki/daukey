import Testing
import DauKeyHook

private let control: Modifiers = .control
private let shift: Modifiers = .shift
private let controlShift: Modifiers = [.control, .shift]
private let keyK: UInt16 = 0x28
private let keyJ: UInt16 = 0x26
private let keyA: UInt16 = 0x00

private func down(_ keyCode: UInt16, _ modifiers: Modifiers = [], isRepeat: Bool = false) -> ShortcutEvent {
    .keyDown(KeyInput(keyCode: keyCode, modifiers: modifiers, characters: "", isRepeat: isRepeat))
}

private func run(_ detector: inout ShortcutDetector, _ events: [ShortcutEvent]) -> [ShortcutDecision] {
    events.map { detector.handle($0) }
}

private func toggles(_ decisions: [ShortcutDecision]) -> Int {
    decisions.count(where: \.toggle)
}

private let pass = ShortcutDecision(toggle: false, consume: false)
private let toggleAndConsume = ShortcutDecision(toggle: true, consume: true)
private let consumeOnly = ShortcutDecision(toggle: false, consume: true)
private let toggleAndPass = ShortcutDecision(toggle: true, consume: false)

@Suite struct ShortcutDetectorTests {
    // MARK: Modifier-only chord

    /// Every reachable chord state followed by every kind of flags change, then a clean release.
    @Test func modifierOnlyTransitions() {
        let both = controlShift
        let prefixes: [[Modifiers]] = [[], [control], [both], [.option]]
        let incoming: [Modifiers] = [[], control, shift, both, .option, [.control, .shift, .function]]
        // Whether the incoming flags event itself toggles; only a full release of an intact chord does.
        let togglesOnIncoming: [[Bool]] = [
            [false, false, false, false, false, false],
            [false, false, false, false, false, false],
            [true, false, false, false, false, false],
            [false, false, false, false, false, false],
        ]
        // Toggles over the whole sequence after appending a clean release.
        let totalToggles: [[Int]] = [
            [0, 0, 0, 1, 0, 0],
            [0, 0, 0, 1, 0, 0],
            [1, 1, 1, 1, 0, 0],
            [0, 0, 0, 0, 0, 0],
        ]
        for (i, prefix) in prefixes.enumerated() {
            for (j, flags) in incoming.enumerated() {
                var detector = ShortcutDetector(config: ShortcutConfig())
                let before = run(&detector, prefix.map(ShortcutEvent.flagsChanged))
                let decision = detector.handle(.flagsChanged(flags))
                let after = detector.handle(.flagsChanged([]))
                #expect(toggles(before) == 0, "prefix \(i) incoming \(j)")
                #expect(decision.toggle == togglesOnIncoming[i][j], "prefix \(i) incoming \(j)")
                #expect(toggles(before + [decision, after]) == totalToggles[i][j], "prefix \(i) incoming \(j)")
                let consumed = (before + [decision, after]).contains { $0.consume }
                #expect(!consumed, "flags events always pass")
            }
        }
    }

    /// Partial release never toggles; only releasing every chord modifier does, in either order.
    /// Caps Lock does not change the result. Two complete cycles toggle exactly twice.
    @Test func releaseOrdersAndRepeatedChords() {
        for first: Modifiers in [.control, .shift] {
            let other: Modifiers = first == .control ? .shift : .control
            for capsLock: Modifiers in [[], .capsLock] {
                var detector = ShortcutDetector(config: ShortcutConfig())
                var decisions: [ShortcutDecision] = []
                for cycle in 0..<2 {
                    decisions += run(&detector, [
                        .flagsChanged(first.union(capsLock)),
                        .flagsChanged(controlShift.union(capsLock)),
                        .flagsChanged(other.union(capsLock)),
                    ])
                    #expect(toggles(decisions) == cycle, "partial release must not toggle")
                    decisions.append(detector.handle(.flagsChanged(capsLock)))
                    #expect(decisions.last == toggleAndPass)
                }
                #expect(decisions.count == 8)
                #expect(toggles(decisions) == 2)
            }
        }
    }

    /// Re-pressing the released modifier before the chord is fully released still toggles once.
    @Test func repressAfterPartialReleaseTogglesOnce() {
        var detector = ShortcutDetector(config: ShortcutConfig())
        let decisions = run(&detector, [
            .flagsChanged(controlShift), .flagsChanged(control), .flagsChanged(controlShift),
            .flagsChanged(shift), .flagsChanged([]),
        ])
        #expect(decisions.map(\.toggle) == [false, false, false, false, true])
    }

    /// Caps Lock changing while the chord is held, with a partial release and re-press, does not change the result:
    /// one toggle per cycle, at the full release, over two cycles in either release order.
    @Test func capsLockChangeMidChordKeepsToggle() {
        let capsLock: Modifiers = .capsLock
        for first: Modifiers in [.control, .shift] {
            // Caps Lock goes off while the chord is held, as in the original sequence.
            let turnsOff: [Modifiers] = [first.union(capsLock), controlShift.union(capsLock), controlShift,
                                         first, controlShift, []]
            // Caps Lock goes on while the chord is held and stays on through the release.
            let turnsOn: [Modifiers] = [first, controlShift, controlShift.union(capsLock),
                                        first.union(capsLock), controlShift.union(capsLock), capsLock]
            for cycle in [turnsOff, turnsOn] {
                var detector = ShortcutDetector(config: ShortcutConfig())
                let decisions = run(&detector, (cycle + cycle).map(ShortcutEvent.flagsChanged))
                let once = Array(repeating: pass, count: 5) + [toggleAndPass]
                #expect(decisions == once + once, "first \(first.rawValue) cycle \(cycle.map(\.rawValue))")
                #expect(toggles(decisions) == 2)
            }
        }
    }

    /// An extra modifier spoils the chord: going back to the exact chord without a clean release does not toggle,
    /// and a new chord after a clean release does.
    @Test func extraModifiersSpoilUntilCleanRelease() {
        for extra: Modifiers in [.option, .command, .function] {
            var detector = ShortcutDetector(config: ShortcutConfig())
            let spoiled = run(&detector, [
                .flagsChanged(controlShift), .flagsChanged(controlShift.union(extra)), .flagsChanged(controlShift),
                .flagsChanged(control), .flagsChanged([]),
            ])
            #expect(spoiled == Array(repeating: pass, count: 5))
            let fresh = run(&detector, [.flagsChanged(controlShift), .flagsChanged([])])
            #expect(fresh == [pass, toggleAndPass])
        }
    }

    /// An ordinary key pressed while the chord is being held spoils it until everything is released;
    /// the key itself is not consumed.
    @Test func ordinaryKeySpoilsHeldChordUntilCleanRelease() {
        for initial: Modifiers in [control, controlShift] {
            var detector = ShortcutDetector(config: ShortcutConfig())
            let spoiled = run(&detector, [
                .flagsChanged(initial), down(keyA, initial), .keyUp(keyA),
                .flagsChanged(controlShift), .flagsChanged([]),
            ])
            #expect(spoiled == Array(repeating: pass, count: 5))
            let fresh = run(&detector, [.flagsChanged(controlShift), .flagsChanged([])])
            #expect(fresh == [pass, toggleAndPass])
        }
    }

    @Test func ordinaryKeyWhileIdleDoesNotSpoilNextChord() {
        var detector = ShortcutDetector(config: ShortcutConfig())
        let decisions = run(&detector, [
            down(keyA), down(keyA, isRepeat: true), .keyUp(keyA), .flagsChanged(controlShift), .flagsChanged([]),
        ])
        #expect(decisions == [pass, pass, pass, pass, toggleAndPass])
    }

    @Test func emptyConfigNeverToggles() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: [], keyCode: nil))
        let decisions = run(&detector, [
            .flagsChanged(control), .flagsChanged([]), .flagsChanged(controlShift), .flagsChanged([]),
            down(keyA), .keyUp(keyA),
        ])
        #expect(decisions == Array(repeating: pass, count: 6))
    }

    // MARK: Modifier+key chord

    @Test func modifierKeyTogglesOnInitialKeyDownAndConsumesPairedKeyUp() {
        for capsLock: Modifiers in [[], .capsLock] {
            var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
            let mods = controlShift.union(capsLock)
            let decisions = run(&detector, [
                .flagsChanged(mods), down(keyK, mods), .keyUp(keyK), .flagsChanged(capsLock),
            ])
            #expect(decisions == [pass, toggleAndConsume, consumeOnly, pass])
        }
    }

    @Test func repeatsAreConsumedWithoutToggling() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        let decisions = run(&detector, [
            down(keyK, controlShift), down(keyK, controlShift, isRepeat: true), down(keyK, controlShift, isRepeat: true),
            .flagsChanged([]), down(keyK, [], isRepeat: true), .keyUp(keyK),
        ])
        #expect(decisions == [toggleAndConsume, consumeOnly, consumeOnly, pass, consumeOnly, consumeOnly])
    }

    /// A repeat of the shortcut key that was never matched is not an initial key-down.
    @Test func unmatchedRepeatPasses() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        let decisions = run(&detector, [down(keyK, controlShift, isRepeat: true), .keyUp(keyK)])
        #expect(decisions == [pass, pass])
    }

    @Test func unmatchedKeysPass() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        let decisions = run(&detector, [
            .keyUp(keyK), .keyUp(keyJ),
            down(keyK, control), .keyUp(keyK),
            down(keyK, [.control, .shift, .option]), .keyUp(keyK),
            down(keyJ, controlShift), .keyUp(keyJ),
            .flagsChanged(controlShift), .flagsChanged([]),
        ])
        #expect(decisions == Array(repeating: pass, count: 10))
    }

    /// A key pressed after the match does not undo the toggle that already happened, and nothing is replayed.
    @Test func laterKeysDoNotUndoToggle() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        let first = run(&detector, [
            .flagsChanged(controlShift), down(keyK, controlShift), down(keyJ, controlShift), .keyUp(keyJ),
            .flagsChanged([.control, .shift, .option]), .keyUp(keyK), .flagsChanged([]),
        ])
        #expect(first == [pass, toggleAndConsume, pass, pass, pass, consumeOnly, pass])
        let second = run(&detector, [down(keyK, controlShift), .keyUp(keyK)])
        #expect(second == [toggleAndConsume, consumeOnly])
        #expect(toggles(first + second) == 2)
    }

    /// A new press of the latched key means its key-up was missed; the latch must not swallow a later key-up.
    @Test func freshPressOfLatchedKeyEndsLatch() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        let decisions = run(&detector, [down(keyK, controlShift), down(keyK), .keyUp(keyK)])
        #expect(decisions == [toggleAndConsume, pass, pass])
    }

    @Test func modifierKeyConfigIgnoresModifierOnlyChord() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        let decisions = run(&detector, [.flagsChanged(control), .flagsChanged(controlShift), .flagsChanged([])])
        #expect(decisions == [pass, pass, pass])
    }

    // MARK: Waiting for release and reset

    @Test func waitForReleaseDefersModifierOnlyDetection() {
        var detector = ShortcutDetector(config: ShortcutConfig())
        detector.waitForRelease(heldModifiers: controlShift, heldKeys: [keyA])
        let waiting = run(&detector, [
            .flagsChanged([]), .flagsChanged(controlShift), .flagsChanged([]), .keyUp(keyA),
        ])
        #expect(waiting == Array(repeating: pass, count: 4))
        let fresh = run(&detector, [.flagsChanged(controlShift), .flagsChanged([])])
        #expect(fresh == [pass, toggleAndPass])
    }

    @Test func waitForReleaseTracksKeysPressedWhileWaiting() {
        var detector = ShortcutDetector(config: ShortcutConfig())
        detector.waitForRelease(heldModifiers: control, heldKeys: [])
        let waiting = run(&detector, [
            down(keyA, control), .flagsChanged([]), .flagsChanged(controlShift), .flagsChanged([]), .keyUp(keyA),
        ])
        #expect(waiting == Array(repeating: pass, count: 5))
        let fresh = run(&detector, [.flagsChanged(controlShift), .flagsChanged([])])
        #expect(fresh == [pass, toggleAndPass])
    }

    @Test func waitForReleaseDefersModifierKeyDetection() {
        var detector = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        detector.waitForRelease(heldModifiers: controlShift, heldKeys: [])
        let waiting = run(&detector, [down(keyK, controlShift), .keyUp(keyK), .flagsChanged([])])
        #expect(waiting == [pass, pass, pass])
        let fresh = run(&detector, [down(keyK, controlShift), .keyUp(keyK)])
        #expect(fresh == [toggleAndConsume, consumeOnly])
    }

    /// The paired key-up of a key that is still held is consumed while waiting; a latch whose key is no longer
    /// held is dropped so it cannot swallow a later key-up.
    @Test func waitForReleaseKeepsOnlyHeldLatch() {
        let config = ShortcutConfig(modifiers: controlShift, keyCode: keyK)
        var held = ShortcutDetector(config: config)
        _ = held.handle(down(keyK, controlShift))
        held.waitForRelease(heldModifiers: controlShift, heldKeys: [keyK])
        #expect(run(&held, [.keyUp(keyK), .flagsChanged([])]) == [consumeOnly, pass])

        var released = ShortcutDetector(config: config)
        _ = released.handle(down(keyK, controlShift))
        released.waitForRelease(heldModifiers: [], heldKeys: [])
        #expect(run(&released, [down(keyK), .keyUp(keyK)]) == [pass, pass])
    }

    @Test func resetClearsChordAndLatch() {
        var modifierOnly = ShortcutDetector(config: ShortcutConfig())
        _ = modifierOnly.handle(.flagsChanged(controlShift))
        modifierOnly.reset()
        #expect(modifierOnly.handle(.flagsChanged([])) == pass)
        #expect(run(&modifierOnly, [.flagsChanged(controlShift), .flagsChanged([])]) == [pass, toggleAndPass])

        var modifierKey = ShortcutDetector(config: ShortcutConfig(modifiers: controlShift, keyCode: keyK))
        _ = modifierKey.handle(down(keyK, controlShift))
        modifierKey.reset()
        #expect(modifierKey.handle(.keyUp(keyK)) == pass)
    }
}
