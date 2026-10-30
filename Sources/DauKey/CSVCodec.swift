/// Comma-separated records, read and written as Unicode scalars so field content round-trips unchanged.
///
/// A field that holds a comma, a quote, a line break, or nothing at all as the only field of its record is quoted,
/// with quotes doubled. CR LF, LF and CR each end a record; empty lines hold no record. Fields are not trimmed.
enum CSVCodec {
    enum Error: Swift.Error, Equatable {
        /// A quoted field is still open at the end of the text.
        case unterminatedQuote(record: Int)
        /// A quote inside an unquoted field.
        case unexpectedQuote(record: Int)
        /// Something other than a comma or a line break after a closing quote.
        case textAfterQuote(record: Int)
    }

    /// The records in `text`; `record` in an error counts records from 1.
    static func decode(_ text: String) throws(Error) -> [[String]] {
        enum State { case fieldStart, unquoted, quoted, closingQuote }
        var records: [[String]] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var state = State.fieldStart
        var afterCR = false

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRecord() {
            // A line with nothing on it holds no record.
            if !fields.isEmpty || state != .fieldStart {
                endField()
                records.append(fields)
                fields = []
            }
            state = .fieldStart
        }

        var scalars = text.unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst() }
        for scalar in scalars {
            defer { afterCR = scalar == "\r" }
            switch (state, scalar) {
            case (.quoted, "\""):
                state = .closingQuote
            case (.quoted, _):
                field.append(scalar)
            case (.closingQuote, "\""):
                field.append(scalar)
                state = .quoted
            case (.fieldStart, "\""):
                state = .quoted
            case (_, ","):
                endField()
                state = .fieldStart
            case (_, "\n") where afterCR:
                // The second half of CR LF; the CR ended the record.
                break
            case (_, "\r"), (_, "\n"):
                endRecord()
            case (.closingQuote, _):
                throw .textAfterQuote(record: records.count + 1)
            case (_, "\""):
                throw .unexpectedQuote(record: records.count + 1)
            case (.fieldStart, _), (.unquoted, _):
                field.append(scalar)
                state = .unquoted
            }
        }
        if state == .quoted { throw .unterminatedQuote(record: records.count + 1) }
        endRecord()
        return records
    }

    /// `rows` as text that `decode` reads back to the same scalars; rows are separated by LF.
    static func encode(_ rows: [[String]]) -> String {
        var text = ""
        for (index, row) in rows.enumerated() {
            if index > 0 { text.unicodeScalars.append("\n") }
            for (column, field) in row.enumerated() {
                if column > 0 { text.unicodeScalars.append(",") }
                append(field, quoted: needsQuotes(field) || (row.count == 1 && field.isEmpty), to: &text)
            }
        }
        return text
    }

    private static func needsQuotes(_ field: String) -> Bool {
        field.unicodeScalars.first == "\u{FEFF}"
            || field.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
    }

    private static func append(_ field: String, quoted: Bool, to text: inout String) {
        guard quoted else {
            text.unicodeScalars.append(contentsOf: field.unicodeScalars)
            return
        }
        text.unicodeScalars.append("\"")
        for scalar in field.unicodeScalars {
            if scalar == "\"" { text.unicodeScalars.append("\"") }
            text.unicodeScalars.append(scalar)
        }
        text.unicodeScalars.append("\"")
    }
}
