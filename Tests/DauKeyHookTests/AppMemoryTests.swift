import Testing
@testable import DauKeyHook

@Suite struct AppMemoryTests {
    @Test func inheritsRestoresAndRecordsOnlyCurrentApp() {
        var memory = AppMemory(memory: [:])
        var enabled = false
        memory.appActivated("app.a", enabled: &enabled)
        #expect(!enabled)
        #expect(memory.memory == ["app.a": false])
        memory.record(true)
        enabled = true
        memory.appActivated("app.b", enabled: &enabled)
        #expect(enabled)
        memory.record(false)
        enabled = false
        memory.appActivated("app.a", enabled: &enabled)
        #expect(enabled)
        #expect(memory.memory == ["app.a": true, "app.b": false])
        memory.appActivated("app.b", enabled: &enabled)
        #expect(!enabled)
        #expect(memory.memory["app.a"] == true)
    }
    @Test func nilAndOwnActivationDoNotStealPreviousApp() {
        var memory = AppMemory(memory: ["app.a": false])
        var enabled = true
        memory.appActivated("app.a", enabled: &enabled)
        memory.appActivated("com.emizuki.daukey", enabled: &enabled)
        #expect(memory.current == "app.a")
        #expect(!enabled)
        #expect(memory.memory == ["app.a": false])
        memory.record(true)
        #expect(memory.memory == ["app.a": true])
        memory.appActivated(nil, enabled: &enabled)
        #expect(memory.current == nil)
        memory.record(false)
        #expect(memory.memory == ["app.a": true])
    }
    @Test func memoryOffKeepsCurrentModeButTracksTarget() {
        var memory = AppMemory(memory: ["com.apple.Notes": false])
        var enabled = true
        memory.setPerAppSwitching(false, enabled: enabled)
        memory.appActivated("com.apple.Notes", enabled: &enabled)
        #expect(enabled)
        #expect(memory.current == "com.apple.Notes")
        memory.record(false)
        enabled = false
        memory.appActivated("com.apple.Safari", enabled: &enabled)
        #expect(!enabled)
        #expect(memory.current == "com.apple.Safari")
        #expect(memory.memory == ["com.apple.Notes": false])
    }
    @Test func enablingRecordsCurrentModeAndUnknownAppsInherit() {
        var memory = AppMemory(memory: ["com.apple.Notes": false, "com.apple.Mail": false], perAppSwitching: false)
        var enabled = true
        memory.appActivated("com.apple.Notes", enabled: &enabled)
        #expect(enabled)
        memory.setPerAppSwitching(true, enabled: enabled)
        #expect(enabled)
        #expect(memory.memory == ["com.apple.Notes": true, "com.apple.Mail": false])
        memory.appActivated("com.apple.Safari", enabled: &enabled)
        #expect(enabled)
        memory.appActivated("com.apple.Mail", enabled: &enabled)
        #expect(!enabled)
        #expect(memory.memory == ["com.apple.Notes": true, "com.apple.Mail": false, "com.apple.Safari": true])
    }
    @Test func ownActivationNeitherRetargetsNorRecords() {
        for perApp in [true, false] {
            var memory = AppMemory(memory: [:], perAppSwitching: perApp)
            var enabled = true
            memory.appActivated("com.apple.Notes", enabled: &enabled)
            let entries = memory.memory
            enabled = false
            memory.appActivated("com.emizuki.daukey", enabled: &enabled)
            #expect(!enabled)
            #expect(memory.current == "com.apple.Notes")
            #expect(memory.memory == entries)
            memory.setPerAppSwitching(!perApp, enabled: enabled)
            memory.setPerAppSwitching(true, enabled: enabled)
            #expect(memory.memory["com.emizuki.daukey"] == nil)
        }
    }
    @Test func enablingWhenAlreadyOnDoesNotRecord() {
        var memory = AppMemory(memory: [:])
        var enabled = true
        memory.appActivated("com.apple.Notes", enabled: &enabled)
        memory.clearEntries()
        memory.setPerAppSwitching(true, enabled: false)
        #expect(memory.memory.isEmpty)
    }
    @Test func resetRetainsExternalTargetWithoutRepopulatingMemory() {
        var memory = AppMemory(memory: ["com.apple.Safari": false])
        var enabled = true
        memory.appActivated("com.apple.Notes", enabled: &enabled)
        memory.clearEntries()
        #expect(memory.memory.isEmpty)
        #expect(memory.current == "com.apple.Notes")
        enabled = false
        memory.record(enabled)
        #expect(memory.memory == ["com.apple.Notes": false])
        memory.appActivated("com.apple.Safari", enabled: &enabled)
        #expect(!enabled)
        enabled = true
        memory.record(enabled)
        memory.appActivated("com.apple.Notes", enabled: &enabled)
        #expect(!enabled)
        #expect(memory.memory == ["com.apple.Notes": false, "com.apple.Safari": true])
    }
}
