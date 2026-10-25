extension Composer {
    func applyCircumflex(_ bases: Set<UInt8>, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        append(key, to: &w, at: position)
    }

    func applyStroke(to w: inout Composition, key: Character, lower: Character, at position: Int) {
        append(key, to: &w, at: position)
    }
}
