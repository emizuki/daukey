import Carbon
import Foundation
import Testing
import DauKeyHook
@testable import DauKey

@Suite @MainActor struct SecureInputNoticeTests {
    @Test func secureInputStateDefaultsToFalse() {
        let name = "DauKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = PreferencesStore(defaults: defaults)
        let startup = store.load()
        let commandPair = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        let snapshotPair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let rules = RuleEditorModel(store: store) { _ in }
        let localization = LocalizationManager(language: .vietnamese, store: store)
        let model = AppModel(
            store: store, initial: startup, permissionGranted: true,
            commands: commandPair.continuation, snapshots: snapshotPair.stream,
            rules: rules, localization: localization
        )
        #expect(model.isSecureInputEnabled == false)
        model.isSecureInputEnabled = true
        #expect(model.isSecureInputEnabled == true)
        defaults.removePersistentDomain(forName: name)
    }

    @Test func runtimeReflectsCarbonSecureInputState() {
        let name = "DauKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let runtime = AppRuntime(defaults: defaults)

        #expect(runtime.model.isSecureInputEnabled == false)
        // Đảo ngược trạng thái để chứng minh checkSecureInput() thực sự cập nhật model
        runtime.model.isSecureInputEnabled = !IsSecureEventInputEnabled()
        runtime.checkSecureInput()
        #expect(runtime.model.isSecureInputEnabled == IsSecureEventInputEnabled())
        defaults.removePersistentDomain(forName: name)
    }

    @Test func secureInputLocalizationStrings() {
        #expect(L10n.string(.secureInputStatus(enabled: false), language: .vietnamese) == "Secure Input đang tắt")
        #expect(L10n.string(.secureInputStatus(enabled: true), language: .vietnamese) == "Secure Input đang bật")
        #expect(L10n.string(.secureInputStatus(enabled: false), language: .english) == "Secure Input is off")
        #expect(L10n.string(.secureInputStatus(enabled: true), language: .english) == "Secure Input is on")
    }
}
