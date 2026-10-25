import Testing
@testable import DauKeyEngine

/// Every row of spec §9.1 ("Spec" column) and examples not covered by the per-rule suites.
@Suite struct SpecRowsTests {
    @Test(arguments: [
        ("Kajn", "Kạn", Options()), ("kius", "kíu", Options()), ("kyeen", "kyên", Options()), ("[[link] ", "[linkư ", Options.off),
        ("kw", "kư", Options()),
        ("xoengr", "xoẻng", Options()), ("ngoaos", "ngoáo", Options()), ("gimf", "gìm", Options()),
        ("pics ", "pics ", Options()), ("techs ", "techs ", Options()), ("Susan ", "Susan ", Options()),
        ("saw ", "saw ", Options()), ("NASA ", "NASA ", Options()), ("cara ", "cara ", Options()),
        ("uow ", "uow ", Options()), ("dzoo", "dzoo", Options()), ("qas", "qas", Options()), ("zero ", "zero ", Options()),
        ("azs", "azs", Options.check), ("woww", "wow", Options()), ("waw", "wa", Options()), ("[w", "[w", Options()),
        ("business", "buinéss", Options.check), ("example", "eamplẽ", Options.check), ("merge", "megẻ", Options()),
        ("extension ", "etensiõn ", Options.check), ("tieengs1 ", "tiếng1 ", Options()),
        ("lowps12 ", "lớp12 ", Options()), ("0]", "0ư", Options()), ("a~as", "a~á", Options.check),
        ("tuwoi", "tươi", Options()), ("u[i", "ươi", Options()), ("woz", "ưoz", Options()),
        ("twoo", "tưoo", Options()), ("][o", "ươo", Options()), ("muowowng", "mươowng", Options()),
        ("[a ", "[a ", Options()), ("[abc] ", "[abc] ", Options()), ("]ic ", "]ic ", Options()),
        ("ginaj", "ginaj", Options()), ("ginju ", "ginju ", Options()), ("ortw", "ỏtw", Options()), ("quw", "quw", Options()), ("gine6", "gine6", Options.vni),
        ("dd<kkas", "kkas", Options.check),
        ("tooi<<<ddanhw ", "ddanhw ", Options()), ("aa<text ", "text ", Options()), ("thuown<", "thuơ", Options()),
        ("th[[[", "th[[", Options()), ("th[[us", "th[us", Options()), ("toi nay vui<<<<<<<<s", "tois", Options()),
        ("lwo.<uwdd", "lwouwdd", Options()), ("ngueeuf", "nguều", Options()), ("ngue6u2", "nguều", Options.vni),
        ("gooongf", "goòng", Options()), ("sooocs", "soóc", Options()), ("goong2", "goòng", Options.vni), ("ddooong ", "đoong ", Options()),
        ("dddd", "ddd", Options()), ("DDTDDDD ", "DDTDDDD ", Options()), ("tieeng€tee ", "tiêng€tê ", Options()),
        ("hu[", "huơ", Options()),
    ])
    func intendedDifferences(_ row: (String, String, Options)) {
        expectSameScalars(typed(row.0, row.2), row.1, row.0)
    }

    // Spec §5.9 examples.
    @Test(arguments: [
        ("ddxaa", "đxâ", Options()), ("ddiws", "điws", Options()), ("ddichf", "đichf", Options()),
        ("ddaafts", "đất", Options()), ("ddaxkas", "đãká", Options()),
        ("ddoao", "đoao", Options()), ("DDKKD", "ĐKKD", Options()), ("BDDS", "BĐS", Options()),
        ("granddad", "grandad", Options()), ("ddaaakkas", "đaakkas", Options()), ("ddxas<<as", "đá", Options()),
        ("dogs", "dogs", Options.off), ("aaaa", "aâ", Options.off), ("ddasskkas", "đaskkas", Options()),
        ("d9a11kka1", "đa1kka1", Options.vni), ("ddwwkas", "đwkas", Options()), ("dd[[kas", "đ[kas", Options()),
    ])
    func segments(_ row: (String, String, Options)) {
        expectSameScalars(typed(row.0, row.2), row.1, row.0)
    }

    @Test func thirtyTwoKeyLimit() {
        let bs = String(repeating: "b", count: 33)
        expectSameScalars(typed(bs + "as", .off), bs + "as")
    }

    @Test func foreignOnsetsOption() {
        let foreign = Options(allowForeignConsonants: true)
        expectSameScalars(typed("zas ", foreign), "zá ")
        expectSameScalars(typed("fans ", foreign), "fán ")
        expectSameScalars(typed("zaas ", Options()), "zaas ")
        expectSameScalars(typed("wa1 ", Options(inputMethod: .vni, allowForeignConsonants: true)), "wá ")
    }
}
