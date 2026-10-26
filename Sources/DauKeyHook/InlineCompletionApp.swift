public enum InlineCompletionApp {
    public static let exceptions: Set<String> = [
        "company.thebrowser.dia", "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    ]

    public static func matches(bundleID: String?, exportedTypeIdentifiers: [String]) -> Bool {
        exportedTypeIdentifiers.contains("org.chromium.extension")
            || bundleID.map { exceptions.contains($0) } == true
    }
}
