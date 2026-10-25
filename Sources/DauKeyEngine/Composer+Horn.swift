extension Composer {
    func applyHornBreve(horn: Bool, breve: Bool, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        append(key, to: &w, at: position)
    }

    func applyBracket(base: UInt8, uppercase: Bool, to w: inout Composition, key: Character, lower: Character, at position: Int) {
        append(key, to: &w, at: position)
    }
}
