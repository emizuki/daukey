import Testing
@testable import DauKeyHook

@Suite struct ChromiumBrowserTests {
    @Test func markerAlone() {
        #expect(ChromiumBrowser.matches(bundleID: "com.google.Chrome", exportedTypeIdentifiers: ["org.chromium.extension"]))
    }
    @Test func exceptionAlone() {
        #expect(ChromiumBrowser.exceptions == ["company.thebrowser.dia"])
        #expect(ChromiumBrowser.matches(bundleID: "company.thebrowser.dia", exportedTypeIdentifiers: []))
    }
    @Test func neither() {
        #expect(!ChromiumBrowser.matches(bundleID: "com.apple.Safari", exportedTypeIdentifiers: ["public.html"]))
        #expect(!ChromiumBrowser.matches(bundleID: nil, exportedTypeIdentifiers: []))
    }
    @Test func markerWithoutBundleID() {
        #expect(ChromiumBrowser.matches(bundleID: nil, exportedTypeIdentifiers: ["org.chromium.extension"]))
    }
}
