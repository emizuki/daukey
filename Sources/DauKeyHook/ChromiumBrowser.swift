public enum ChromiumBrowser {
    public static let exceptions: Set<String> = ["company.thebrowser.dia"]

    public static func matches(bundleID: String?, exportedTypeIdentifiers: [String]) -> Bool {
        exportedTypeIdentifiers.contains("org.chromium.extension")
            || bundleID.map { exceptions.contains($0) } == true
    }
}
