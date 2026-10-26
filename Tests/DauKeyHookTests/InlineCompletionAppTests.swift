import Testing
@testable import DauKeyHook

@Suite struct InlineCompletionAppTests {
    @Test func chromiumMarkerEnablesTheWorkaround() {
        #expect(InlineCompletionApp.matches(bundleID: "com.google.Chrome", exportedTypeIdentifiers: ["org.chromium.extension"]))
        #expect(InlineCompletionApp.matches(bundleID: nil, exportedTypeIdentifiers: ["org.chromium.extension"]))
    }
    @Test func knownInlineCompletionAppsNeedNoMarker() {
        for bundleID in ["company.thebrowser.dia", "com.apple.Safari", "com.apple.SafariTechnologyPreview"] {
            #expect(InlineCompletionApp.matches(bundleID: bundleID, exportedTypeIdentifiers: ["public.html"]))
        }
    }
    @Test func appExceptionsMatchOnlyExactBundleIDs() {
        for bundleID in [
            "com.apple.safari", "com.apple.SafariTechnologyPreview.beta", "com.apple.Safari.extra",
            "prefix.com.apple.Safari", "com.apple.SafariTechnology", "company.thebrowser.dia.beta",
        ] {
            #expect(!InlineCompletionApp.matches(bundleID: bundleID, exportedTypeIdentifiers: ["public.html"]))
        }
    }
    @Test func ordinaryAppsIncludingFirefoxAndElectronAreUnaffected() {
        for bundleID: String? in [nil, "org.mozilla.firefox", "org.mozilla.nightly", "com.tinyspeck.slackmacgap", "com.microsoft.VSCode"] {
            #expect(!InlineCompletionApp.matches(bundleID: bundleID, exportedTypeIdentifiers: ["public.html"]))
        }
    }
}
