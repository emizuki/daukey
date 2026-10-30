import Testing
@testable import DauKeyEngine

@Suite struct SpellingExceptionTests {
    @Test(arguments: [
        ("Bawsc Kanj ", "Bắc Kạn "), ("DDawsk Lawsk ", "Đắk Lắk "), ("Kroong Busk ", "Krông Búk "),
        ("Chuw Pawh ", "Chư Păh "), ("Ea Droong ", "Ea Drông "), ("xe buyts ", "xe buýt "),
        ("mosa ", "móa "), ("mora ", "mỏa "), ("Laswk ", "Lắk "), ("kuawng ", "kuăng "),
    ])
    func exceptionWordsType(_ row: (String, String)) { expectSameScalars(typed(row.0), row.1, row.0) }

    @Test func vniTypesExceptions() {
        let vni = Options(inputMethod: .vni)
        expectSameScalars(typed("La81k ", vni), "Lắk ", "La81k")
        expectSameScalars(typed("La De6e6 ", vni), "La Dêê ", "La De6e6")
    }

    @Test func exceptionsIgnoreCase() {
        expectSameScalars(typed("KRoong Busk "), "KRông Búk ", "KRoong")
        expectSameScalars(typed("KROONG BUSK "), "KRÔNG BÚK ", "caps")
    }

    @Test func backspaceInsideExceptionWord() {
        expectSameScalars(typed("Lawsk<k "), "Lắk ", "Lawsk<k")
        expectSameScalars(typed("Kroong<<ng"), "Krông", "Kroong<<ng")
    }

    @Test func englishWordsRestore() {
        expectSameScalars(typed("bloom "), "bloom ", "bloom")
        expectSameScalars(typed("Lakers "), "Lakers ", "Lakers")
    }

    @Test func exceptionsFollowToneStyle() {
        let modern = Options(toneStyle: .modern)
        expectSameScalars(typed("mosa ", modern), "moá ", "modern móa")
        expectSameScalars(typed("mora ", modern), "moả ", "modern mỏa")
    }

    @Test func exactToneOnly() {
        expectSameScalars(typed("Lawjk "), "Lawjk ", "lặk is not an exception")
    }
}

@Suite struct SpellingRuleTests {
    @Test(arguments: [
        ("yts ", "yts "), ("ghas ", "ghas "), ("byeen ", "byeen "), ("kos ", "kos "), ("boawsc ", "boawsc "),
        ("cef ", "cef "), ("ngeef ", "ngeef "), ("kuyts ", "kuyts "),
    ])
    func rejectedSyllablesStayRaw(_ row: (String, String)) { expectSameScalars(typed(row.0), row.1, row.0) }

    @Test(arguments: [
        ("quyts ", "quýt "), ("huyts ", "huýt "), ("gif ", "gì "), ("ghi ", "ghi "), ("nghieeng ", "nghiêng "),
        ("muaf ", "mùa "), ("vuoong ", "vuông "), ("chooif ", "chồi "), ("vieec <j", "việc"), ("beep ", "bêp "),
        ("kyf ", "kỳ "), ("kias ", "kía "), ("gieets ", "giết "), ("Bawsc Kanj ", "Bắc Kạn "),
    ])
    func validWordsUnchanged(_ row: (String, String)) { expectSameScalars(typed(row.0), row.1, row.0) }

    @Test func rulesIgnoreForeignOnsetOption() {
        let foreign = Options(allowForeignConsonants: true)
        expectSameScalars(typed("kos ", foreign), "kos ", "R1 with foreign onsets")
        expectSameScalars(typed("boawsc ", foreign), "boawsc ", "L1 with foreign onsets")
        expectSameScalars(typed("zas ", foreign), "zá ", "foreign onset still works")
    }

    @Test func rulesApplyWithSpellingOff() {
        expectSameScalars(typed("yts ", .off), "yts ", "R3: yt is not completable")
        expectSameScalars(typed("kos ", .off), "kó ", "kó is a prefix of the exception kót")
        expectSameScalars(typed("Kroongs ", .off), "Krôngs ", "krông with acute is not completable")
        expectSameScalars(typed("ddaxkas"), "đãkas", "đ word: ká is not completable")
    }
}
