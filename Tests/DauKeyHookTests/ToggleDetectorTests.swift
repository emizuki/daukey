import Testing
@testable import DauKeyHook

@Suite struct ToggleDetectorTests {
    @Test func transitionTable() {
        let c: Modifiers = .control, s: Modifiers = .shift
        let both: Modifiers = [c, s]
        let states: [[Modifiers]] = [[], [c], [both], [.option]]
        let incoming: [Modifiers] = [[], c, s, both, .option, [both, .function]]
        let expected = [[false,false,false,false,false,false], [false,false,false,false,false,false],
                        [true,true,true,false,false,false], [false,false,false,false,false,false]]
        let expectedStates: [[ToggleDetector.State]] = [
            [.idle, .arming, .arming, .armed, .spoiled, .spoiled],
            [.idle, .arming, .arming, .armed, .spoiled, .spoiled],
            [.idle, .spoiled, .spoiled, .armed, .spoiled, .spoiled],
            [.idle, .spoiled, .spoiled, .spoiled, .spoiled, .spoiled],
        ]
        for (i, prefix) in states.enumerated() {
            for (j, flags) in incoming.enumerated() {
                var detector = ToggleDetector()
                for flag in prefix { _ = detector.flagsChanged(flag) }
                #expect(detector.flagsChanged(flags) == expected[i][j])
                #expect(detector.state == expectedStates[i][j])
            }
        }
    }
    @Test func releaseOrdersAndRepeatedChords() {
        for first: Modifiers in [.control, .shift] {
            var detector = ToggleDetector()
            for _ in 0..<2 {
                #expect(detector.flagsChanged(first.union(.capsLock)) == false)
                #expect(detector.flagsChanged([.control, .shift, .capsLock]) == false)
                #expect(detector.flagsChanged([.control, .shift]) == false)
                #expect(detector.flagsChanged(first) == true)
                #expect(detector.flagsChanged([.control, .shift]) == false)
                #expect(detector.flagsChanged([]) == false)
            }
        }
    }
    @Test func disturbancesAndExtraModifiersSpoilUntilEmpty() {
        for extra: Modifiers in [.option, .command, .function] {
            var detector = ToggleDetector()
            #expect(detector.flagsChanged([.control, .shift]) == false)
            #expect(detector.flagsChanged([.control, .shift, extra]) == false)
            #expect(detector.flagsChanged([.control, .shift]) == false)
            #expect(detector.flagsChanged(.control) == false)
            #expect(detector.flagsChanged([]) == false)
        }
        for initial: Modifiers in [.control, [.control, .shift]] {
            var detector = ToggleDetector()
            _ = detector.flagsChanged(initial)
            detector.disturb()
            #expect(detector.flagsChanged([.control, .shift]) == false)
            #expect(detector.flagsChanged([]) == false)
            _ = detector.flagsChanged([.control, .shift])
            #expect(detector.flagsChanged([]) == true)
        }
        var idle = ToggleDetector()
        idle.disturb()
        _ = idle.flagsChanged([.control, .shift])
        #expect(idle.flagsChanged([]) == true)
    }
}
