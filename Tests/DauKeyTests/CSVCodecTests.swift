import Testing
@testable import DauKey

@Suite struct CSVCodecTests {
    @Test func decodesRecordsAndFields() throws {
        #expect(try CSVCodec.decode("vn,Việt Nam\nhn,Hà Nội") == [["vn", "Việt Nam"], ["hn", "Hà Nội"]])
        #expect(try CSVCodec.decode("one") == [["one"]])
    }

    @Test func everyLineTerminatorEndsARecordAndAFinalOneAddsNoRecord() throws {
        let expected = [["a", "b"], ["c", "d"]]
        #expect(try CSVCodec.decode("a,b\r\nc,d\r\n") == expected)
        #expect(try CSVCodec.decode("a,b\nc,d\n") == expected)
        #expect(try CSVCodec.decode("a,b\rc,d") == expected)
        #expect(try CSVCodec.decode("a,b\r\n\r\nc,d\n\n") == expected)
    }

    @Test func emptyCellsAreKept() throws {
        #expect(try CSVCodec.decode(",") == [["", ""]])
        #expect(try CSVCodec.decode("a,,b,\n,x") == [["a", "", "b", ""], ["", "x"]])
        #expect(try CSVCodec.decode("\"\"") == [[""]])
        #expect(try CSVCodec.decode("\"\",\"\"\r\n") == [["", ""]])
    }

    @Test func emptyTextHasNoRecords() throws {
        #expect(try CSVCodec.decode("") == [])
        #expect(try CSVCodec.decode("\n\r\n") == [])
    }

    @Test func quotedFieldsKeepCommasQuotesLineBreaksAndSpaces() throws {
        let text = "vn,\" dòng 1, \"\"quote\"\"\n dòng 2 \"\r\nx,\"a\r\nb\""
        let records = try CSVCodec.decode(text)
        #expect(records.count == 2)
        #expect(records[0][0] == "vn")
        #expect(records[0][1].unicodeScalars.elementsEqual(" dòng 1, \"quote\"\n dòng 2 ".unicodeScalars))
        #expect(records[1][1].unicodeScalars.elementsEqual("a\r\nb".unicodeScalars))
        #expect(try CSVCodec.decode(" a , b ") == [[" a ", " b "]])
    }

    @Test func unterminatedQuoteIsAnError() {
        #expect(throws: CSVCodec.Error.unterminatedQuote(record: 2)) {
            try CSVCodec.decode("vn,Việt Nam\nhn,\"Hà Nội\nsg,Sài Gòn")
        }
        #expect(throws: CSVCodec.Error.unterminatedQuote(record: 1)) { try CSVCodec.decode("\"") }
    }

    @Test func quotesOutsideAQuotedFieldAreAnError() {
        #expect(throws: CSVCodec.Error.unexpectedQuote(record: 1)) { try CSVCodec.decode("a\"b,c") }
        #expect(throws: CSVCodec.Error.textAfterQuote(record: 2)) { try CSVCodec.decode("a,b\n\"x\"y,c") }
        #expect(throws: CSVCodec.Error.textAfterQuote(record: 1)) { try CSVCodec.decode("\"x\" ,c") }
    }

    @Test func leadingByteOrderMarkIsNotPartOfTheFirstField() throws {
        #expect(try CSVCodec.decode("\u{FEFF}vn,Việt Nam") == [["vn", "Việt Nam"]])
    }

    @Test func combiningMarksAfterQuotesAndCommasStaySeparateScalars() throws {
        // As Characters, a quote or a comma followed by a combining mark is one grapheme.
        let text = "\"\"\"\u{0301}\",\u{0301}x\n\"a,\u{0300}\""
        let records = try CSVCodec.decode(text)
        #expect(records.count == 2)
        #expect(records[0].map { Array($0.unicodeScalars) } == [["\"", "\u{0301}"], ["\u{0301}", "x"]])
        #expect(records[1].map { Array($0.unicodeScalars) } == [["a", ",", "\u{0300}"]])
    }

    @Test func encodeQuotesOnlyFieldsThatNeedIt() {
        #expect(CSVCodec.encode([["vn", "Việt Nam"], ["hn", "Hà Nội"]]) == "vn,Việt Nam\nhn,Hà Nội")
        #expect(CSVCodec.encode([["a,b", "say \"hi\"", "x\ny", "x\ry", " pad "]])
            == "\"a,b\",\"say \"\"hi\"\"\",\"x\ny\",\"x\ry\", pad ")
        #expect(CSVCodec.encode([[""]]) == "\"\"")
        #expect(CSVCodec.encode([["", ""]]) == ",")
        #expect(CSVCodec.encode([]) == "")
    }

    @Test func encodedRowsDecodeToTheSameScalars() throws {
        let rows = [
            ["\u{FEFF}x", "\"\u{0301}"],
            ["vn", " dòng 1, \"quote\"\n dòng 2 "],
            [""],
            ["", "a\r\nb", ",\u{0300}"],
            ["viê\u{0323}t", "\r"],
        ]
        let decoded = try CSVCodec.decode(CSVCodec.encode(rows))
        #expect(decoded.map { $0.map { Array($0.unicodeScalars) } } == rows.map { $0.map { Array($0.unicodeScalars) } })
    }
}
