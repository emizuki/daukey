import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) -> (status: SMAppService.Status, error: String?) {
        let errorDescription: String?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
        return (status: status, error: errorDescription)
    }
}
