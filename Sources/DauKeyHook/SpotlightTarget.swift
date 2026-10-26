public enum SpotlightTarget {
    public static let bundleIDs: Set<String> = ["com.apple.Spotlight", "com.apple.campo"]

    public static func matches(bundleID: String?) -> Bool {
        bundleID.map { bundleIDs.contains($0) } == true
    }
}
