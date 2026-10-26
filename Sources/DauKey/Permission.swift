import AppKit
import ApplicationServices

@MainActor
enum Permission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static func openSettings() {
        // The SDK exposes the prompt key as a mutable C global; use its stable value.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }
}
