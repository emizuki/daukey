import Testing
@testable import DauKeyEngine

@Suite struct MarkTests {
    @Test(arguments: [
        ("tieen", "tiên"), ("tiene", "tiên"), ("baa", "bâ"), ("aaa", "aa"), ("xooong", "xoong"),
        ("gooongf", "goongf"), ("tuana", "tuân"), ("banana", "bânna"), ("Aa", "Â"), ("tieengs", "tiếng"),
        ("gieengs", "giếng"), ("cheese", "chée"), ("viejec", "việc"), ("vieejc", "việc"), ("aae", "âe"), ("eea", "êa"),
    ])
    func circumflexTelex(_ row: (String, String)) {
        expectSameScalars(composed(row.0), row.1, row.0)
    }

    @Test(arguments: [("tie6n", "tiên"), ("a66", "a6"), ("uo6", "uô"), ("oa6", "oa6"), ("tie6ng1", "tiếng")])
    func circumflexVNI(_ row: (String, String)) {
        expectSameScalars(composed(row.0, .vni), row.1, row.0)
    }

    @Test(arguments: [
        ("dd", "đ"), ("did", "đi"), ("ddd", "dd"), ("dddd", "ddd"), ("DDDD", "DDD"), ("bdd", "bđ"), ("BDDS", "BĐS"),
        ("anddehit", "anđehit"), ("add", "add"), ("bddd", "bdd"), ("disdain", "đíain"),
    ])
    func strokeTelex(_ row: (String, String)) {
        expectSameScalars(composed(row.0), row.1, row.0)
    }

    @Test(arguments: [("d9", "đ"), ("d99", "d9"), ("bd9", "bđ"), ("d9i", "đi"), ("d9d99", "đd9")])
    func strokeVNI(_ row: (String, String)) {
        expectSameScalars(composed(row.0, .vni), row.1, row.0)
    }

    @Test func strokeTurnsSpellingOff() {
        // Spec §5.9: after `đ`, `x` starts a segment and the circumflex applies inside it.
        expectSameScalars(composed("ddxaa"), "đxâ")
        expectSameScalars(composed("dxaa"), "dxaa")
        // Gating still applies inside a segment.
        expectSameScalars(composed("ddoao"), "đoao")
        expectSameScalars(composed("ddichf"), "đichf")
    }
}
