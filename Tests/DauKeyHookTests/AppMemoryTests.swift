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
}
