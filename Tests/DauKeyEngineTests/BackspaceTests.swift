import Testing
@testable import DauKeyEngine

/// Keys and display after one Backspace on the composition of `keys`.
private func backspace(_ keys: String, _ options: Options = Options()) -> (keys: String, display: String) {
    let composer = Composer(options: options)
    let remaining = composer.keysAfterBackspace(Array(keys))
    return (String(remaining), composer.display(remaining))
}

@Suite struct BackspaceTests {
    // Spec §6.2 table: (keys, keys after ⌫, display after ⌫, options).
    @Test(arguments: [
        ("hoanf", "hoaf", "hòa", Options()), ("toans", "toas", "toá", Options.modern), ("mas", "m", "m", Options()),
        ("tieens", "tiees", "tiế", Options()), ("tiees", "ti", "ti", Options()), ("ass", "a", "a", Options()),
        ("w", "", "", Options()), ("ww", "", "", Options()), ("textt", "text", "tẽt", Options()),
        ("wex", "we", "ưe", Options()), ("uonw", "uow", "ươ", Options()), ("nguoiwf", "nguowf", "ngườ", Options()),
        ("nguow", "nguw", "ngư", Options()), ("thuown", "thuow", "thuơ", Options()), ("siste", "sist", "sít", Options()),
        ("bxas", "bx", "bx", Options.off), ("asx", "", "", Options.off), ("asz", "", "", Options()),
        ("hosza", "hosz", "ho", Options.modern), ("wszw", "", "", Options()), ("woww", "wo", "ưo", Options()),
        ("a11", "a", "a", Options.vni), ("tieengs", "tieens", "tiến", Options()), ("dd", "", "", Options()),
        ("[[", "", "", Options()), ("bdd", "b", "b", Options()), ("]ow", "]", "ư", Options()),
        ("pu7o7", "pu7", "pư", Options.vni), ("sdd[d", "sd", "sd", Options()),
        ("ddaxbas", "ddaxb", "đãb", Options()), ("d9a4ba1", "d9a4b", "đãb", Options.vni),
        ("aaa", "a", "a", Options()), ("aaww", "a", "a", Options()),
    ])
    func specRows(_ row: (String, String, String, Options)) {
        let result = backspace(row.0, row.3)
        #expect(result.keys == row.1, "\(row.0): keys \(result.keys), expected \(row.1)")
        expectSameScalars(result.display, row.2, row.0)
    }
}
