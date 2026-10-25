import Testing
@testable import DauKeyEngine

private func placed(_ text: String, _ tone: Tone, _ style: ToneStyle = .old) -> String {
    let list = elements(text)
    return Render.string(list, tone: tone, toneAt: Placement.target(list, tone: tone, style: style, onsets: .native))
}

@Suite struct PlacementTests {
    @Test(arguments: [
        ("người", "ngươi", Tone.grave), ("mứa", "mưa", .acute), ("tiến", "tiên", .acute), ("thuở", "thuơ", .hook),
        ("khuấy", "khuây", .acute), ("gửi", "gưi", .hook), ("toán", "toan", .acute), ("hoàn", "hoan", .grave),
        ("huỳnh", "huynh", .grave), ("huýt", "huyt", .acute), ("ngoài", "ngoai", .grave), ("xoáy", "xoay", .acute),
        ("khuỷu", "khuyu", .hook), ("ngoẹo", "ngoeo", .dot), ("mái", "mai", .acute), ("múa", "mua", .acute),
        ("mía", "mia", .acute), ("hỏi", "hoi", .hook), ("cáu", "cau", .acute), ("quý", "quy", .acute),
        ("già", "gia", .grave), ("gì", "gi", .grave), ("giếng", "giêng", .acute), ("quỳnh", "quynh", .grave),
        ("rượu", "rươu", .dot), ("được", "đươc", .dot),
    ])
    func rulesOneToFive(_ row: (String, String, Tone)) {
        expectSameScalars(placed(row.1, row.2), row.0, row.1)
    }

    @Test func oldAndModernStyles() {
        expectSameScalars(placed("hoa", .grave, .old), "hòa")
        expectSameScalars(placed("hoa", .grave, .modern), "hoà")
        expectSameScalars(placed("hoe", .grave, .old), "hòe")
        expectSameScalars(placed("hoe", .grave, .modern), "hoè")
        expectSameScalars(placed("thuy", .hook, .old), "thủy")
        expectSameScalars(placed("thuy", .hook, .modern), "thuỷ")
        expectSameScalars(placed("hoan", .grave, .modern), "hoàn")
        expectSameScalars(placed("quy", .acute, .modern), "quý")
    }

    @Test func fallbackForNonSyllables() {
        expectSameScalars(placed("business", .acute), "businéss")
        expectSameScalars(placed("aeiou", .acute), "aéiou")   // open run of n ≥ 3 takes its second letter
        expectSameScalars(placed("ai1", .acute), "ái1")       // an `other` element is not a coda
        expectSameScalars(placed("điain", .acute), "điaín")
        expectSameScalars(placed("site", .acute), "sité")
        expectSameScalars(placed("chee", .acute), "chée")
        expectSameScalars(placed("tet", .tilde), "tẽt")
        #expect(Placement.target(elements("bx"), tone: .acute, style: .old, onsets: .native) == nil)
        #expect(Placement.target(elements("a1"), tone: .acute, style: .old, onsets: .native) == 0)
    }
}
