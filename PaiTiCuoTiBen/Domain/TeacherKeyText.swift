import Foundation
import PDFKit

struct TeacherKeyInspection: Equatable {
    var status: TeacherKeyStatus
    var text: String
    var note: String
}

/// Reads a teacher key on device. Word is first, then a PDF text layer, then an image left for OCR.
enum TeacherKeyText {
    static let textLimit = 20_000

    static func inspect(format: TeacherKeyFormat, data: Data) -> TeacherKeyInspection {
        switch format {
        case .doc:
            return TeacherKeyInspection(
                status: .failed,
                text: "",
                note: "这份 .doc 无法在本机解开。请另存为 docx，或改用图片。"
            )
        case .docx:
            return inspectDocx(data)
        case .pdf:
            return inspectPDF(data)
        case .image:
            return TeacherKeyInspection(status: .pending, text: "", note: "")
        case .unknown:
            return TeacherKeyInspection(
                status: .failed,
                text: "",
                note: "这份老师标答格式无法识别。请改用 docx 或图片。"
            )
        }
    }

    static func plainText(fromOCR lines: [String]) -> TeacherKeyInspection {
        let text = cap(lines.joined(separator: "\n"))
        if text.isEmpty {
            return TeacherKeyInspection(
                status: .failed,
                text: "",
                note: "老师标答图片没有识别出文字。请改用 docx，或换一张更清晰的图片。"
            )
        }
        return TeacherKeyInspection(status: .parsed, text: text, note: "")
    }

    private static func inspectDocx(_ data: Data) -> TeacherKeyInspection {
        let failed = TeacherKeyInspection(
            status: .failed,
            text: "",
            note: "这份 Word 没有解析出文字。请另存为 docx，或改用图片。"
        )
        guard let members = try? ZipArchiveReader.members(in: data),
              let document = members.first(where: { $0.name.replacingOccurrences(of: "\\", with: "/").lowercased() == "word/document.xml" }),
              let xml = String(data: document.data, encoding: .utf8) else {
            return failed
        }
        let text = cap(DocxXML.plainText(xml))
        guard !text.isEmpty else { return failed }
        return TeacherKeyInspection(status: .parsed, text: text, note: "")
    }

    private static func inspectPDF(_ data: Data) -> TeacherKeyInspection {
        let failed = TeacherKeyInspection(
            status: .failed,
            text: "",
            note: "这份 PDF 没有可选中的文字。请改用 docx 或图片。"
        )
        let text = cap(PDFTextExtractor.string(from: data))
        guard !text.isEmpty else { return failed }
        return TeacherKeyInspection(status: .parsed, text: text, note: "")
    }

    private static func cap(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= textLimit { return trimmed }
        return String(trimmed.prefix(textLimit))
    }
}

enum DocxXML {
    static func plainText(_ xml: String) -> String {
        let prepared = xml
            .replacingOccurrences(of: "<w:tab/>", with: " ")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
            .replacingOccurrences(of: "<w:cr/>", with: "\n")
        let paragraphs = prepared.components(separatedBy: "</w:p>")
        let lines = paragraphs.compactMap { paragraph -> String? in
            let pieces = capture(paragraph)
            let line = decodeEntities(pieces.joined())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        return lines.joined(separator: "\n")
    }

    private static func capture(_ paragraph: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<w:t\b[^>]*>([\s\S]*?)</w:t>"#) else {
            return []
        }
        let range = NSRange(paragraph.startIndex..<paragraph.endIndex, in: paragraph)
        return regex.matches(in: paragraph, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: paragraph) else { return nil }
            return String(paragraph[swiftRange])
        }
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Numbered lines in a teacher key replace `canonical.text` only. Steps stay system-generated.
enum TeacherAnswerAligner {
    static func map(from text: String) -> [String: String] {
        var answers: [String: String] = [:]
        var current: String?
        var buffer: [String] = []
        func flush() {
            guard let current else { return }
            let answer = buffer
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty, answers[current] == nil {
                answers[current] = answer
            }
        }
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if let split = QuestionNumbers.split(line) {
                flush()
                current = split.number
                buffer = split.rest.isEmpty ? [] : [split.rest]
            } else if current != nil {
                buffer.append(line)
            }
        }
        flush()
        return answers
    }

    /// Returns the answer text to store. Solution steps are left untouched by the caller.
    static func alignedText(
        systemText: String,
        questionNumber: String,
        answers: [String: String],
        plainText: String,
        soleQuestion: Bool
    ) -> String {
        let number = QuestionNumbers.normalize(questionNumber)
        if !number.isEmpty, let teacher = answers[number]?.trimmingCharacters(in: .whitespacesAndNewlines), !teacher.isEmpty {
            return teacher
        }
        let plain = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if soleQuestion, answers.isEmpty, !plain.isEmpty, !plain.contains("\n"), plain.count <= 200 {
            return plain
        }
        return systemText
    }
}

enum ZipArchiveReader {
    struct Member {
        var name: String
        var data: Data
    }

    static func members(in data: Data) throws -> [Member] {
        guard let eocd = findEOCD(data) else { throw ZipReadError.invalid }
        let count = Int(u16(data, eocd + 10))
        var cursor = Int(u32(data, eocd + 16))
        var members: [Member] = []
        for _ in 0..<count {
            guard cursor + 46 <= data.count, u32(data, cursor) == 0x0201_4B50 else { throw ZipReadError.invalid }
            let method = Int(u16(data, cursor + 10))
            let compressedSize = Int(u32(data, cursor + 20))
            let nameLength = Int(u16(data, cursor + 28))
            let extraLength = Int(u16(data, cursor + 30))
            let commentLength = Int(u16(data, cursor + 32))
            let localOffset = Int(u32(data, cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw ZipReadError.invalid }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            let payload = try inflateMember(data, localOffset: localOffset, method: method, compressedSize: compressedSize)
            members.append(Member(name: name, data: payload))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return members
    }

    private static func inflateMember(_ data: Data, localOffset: Int, method: Int, compressedSize: Int) throws -> Data {
        guard localOffset + 30 <= data.count, u32(data, localOffset) == 0x0403_4B50 else { throw ZipReadError.invalid }
        let nameLength = Int(u16(data, localOffset + 26))
        let extraLength = Int(u16(data, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        guard compressedSize >= 0, start + compressedSize <= data.count else { throw ZipReadError.invalid }
        let compressed = data.subdata(in: start..<(start + compressedSize))
        switch method {
        case 0:
            return compressed
        case 8:
            return try RawInflate.decompress(compressed)
        default:
            throw ZipReadError.invalid
        }
    }

    private static func findEOCD(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let start = max(0, data.count - 22 - 65_535)
        var index = data.count - 22
        while index >= start {
            if u32(data, index) == 0x0605_4B50 {
                return index
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

struct ZipReadError: Error {
    static let invalid = ZipReadError()
}

/// Raw DEFLATE (ZIP method 8), matching RFC 1951.
enum RawInflate {
    static let outputLimit = 8_000_000

    static func decompress(_ data: Data) throws -> Data {
        let reader = BitReader(data)
        var output: [UInt8] = []
        while true {
            let final = try reader.bits(1)
            let kind = try reader.bits(2)
            switch kind {
            case 0:
                reader.align()
                let length = try reader.bits(16)
                let complement = try reader.bits(16)
                guard length ^ 0xFFFF == complement else { throw ZipReadError.invalid }
                let bytes = try reader.bytes(length)
                try append(bytes, to: &output)
            case 1:
                try decodeBlock(reader, output: &output, literal: fixedLiteral(), distance: fixedDistance())
            case 2:
                let tables = try dynamicTables(reader)
                try decodeBlock(reader, output: &output, literal: tables.literal, distance: tables.distance)
            default:
                throw ZipReadError.invalid
            }
            if final == 1 { break }
        }
        return Data(output)
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static func fixedLiteral() -> [HuffKey: Int] {
        var lengths = [Int](repeating: 8, count: 144)
        lengths += [Int](repeating: 9, count: 112)
        lengths += [Int](repeating: 7, count: 24)
        lengths += [Int](repeating: 8, count: 8)
        return canon(lengths)
    }

    private static func fixedDistance() -> [HuffKey: Int] {
        canon([Int](repeating: 5, count: 32))
    }

    private static func canon(_ lengths: [Int]) -> [HuffKey: Int] {
        guard let maxBits = lengths.max(), maxBits > 0 else { return [:] }
        var counts = [Int](repeating: 0, count: maxBits + 1)
        for length in lengths where length > 0 {
            counts[length] += 1
        }
        var nextCode = [Int](repeating: 0, count: maxBits + 1)
        var code = 0
        if maxBits >= 1 {
            for bits in 1...maxBits {
                code = (code + counts[bits - 1]) << 1
                nextCode[bits] = code
            }
        }
        var table: [HuffKey: Int] = [:]
        for (symbol, length) in lengths.enumerated() where length > 0 {
            table[HuffKey(code: nextCode[length], length: length)] = symbol
            nextCode[length] += 1
        }
        return table
    }

    private static func decodeBlock(
        _ reader: BitReader,
        output: inout [UInt8],
        literal: [HuffKey: Int],
        distance: [HuffKey: Int]
    ) throws {
        while true {
            let symbol = try decodeSymbol(reader, literal)
            if symbol < 256 {
                try append([UInt8(symbol)], to: &output)
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthBase.indices.contains(lengthIndex) else { throw ZipReadError.invalid }
                let length = lengthBase[lengthIndex] + (try reader.bits(lengthExtra[lengthIndex]))
                let distanceSymbol = try decodeSymbol(reader, distance)
                guard distanceBase.indices.contains(distanceSymbol) else { throw ZipReadError.invalid }
                let offset = distanceBase[distanceSymbol] + (try reader.bits(distanceExtra[distanceSymbol]))
                guard offset > 0, offset <= output.count else { throw ZipReadError.invalid }
                for _ in 0..<length {
                    try append([output[output.count - offset]], to: &output)
                }
            }
        }
    }

    private static func dynamicTables(_ reader: BitReader) throws -> (literal: [HuffKey: Int], distance: [HuffKey: Int]) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengths[codeLengthOrder[index]] = try reader.bits(3)
        }
        let alphabet = canon(codeLengths)
        var lengths: [Int] = []
        let total = literalCount + distanceCount
        while lengths.count < total {
            let symbol = try decodeSymbol(reader, alphabet)
            if symbol < 16 {
                lengths.append(symbol)
            } else if symbol == 16 {
                guard let previous = lengths.last else { throw ZipReadError.invalid }
                let extra = try reader.bits(2) + 3
                guard lengths.count + extra <= total else { throw ZipReadError.invalid }
                lengths.append(contentsOf: [Int](repeating: previous, count: extra))
            } else if symbol == 17 {
                let extra = try reader.bits(3) + 3
                guard lengths.count + extra <= total else { throw ZipReadError.invalid }
                lengths.append(contentsOf: [Int](repeating: 0, count: extra))
            } else if symbol == 18 {
                let extra = try reader.bits(7) + 11
                guard lengths.count + extra <= total else { throw ZipReadError.invalid }
                lengths.append(contentsOf: [Int](repeating: 0, count: extra))
            } else {
                throw ZipReadError.invalid
            }
        }
        guard lengths.count == total else { throw ZipReadError.invalid }
        return (canon(Array(lengths.prefix(literalCount))), canon(Array(lengths.suffix(distanceCount))))
    }

    private static func decodeSymbol(_ reader: BitReader, _ table: [HuffKey: Int]) throws -> Int {
        var code = 0
        for length in 1...15 {
            code = (code << 1) | (try reader.bits(1))
            if let symbol = table[HuffKey(code: code, length: length)] {
                return symbol
            }
        }
        throw ZipReadError.invalid
    }

    private static func append(_ bytes: [UInt8], to output: inout [UInt8]) throws {
        guard output.count + bytes.count <= outputLimit else { throw ZipReadError.invalid }
        output.append(contentsOf: bytes)
    }
}

private struct HuffKey: Hashable {
    var code: Int
    var length: Int
}

private final class BitReader {
    private let data: Data
    private var index = 0
    private var accumulator = 0
    private var count = 0

    init(_ data: Data) {
        self.data = data
    }

    func bits(_ width: Int) throws -> Int {
        guard width > 0 else { return 0 }
        while count < width {
            guard index < data.count else { throw ZipReadError.invalid }
            accumulator |= Int(data[index]) << count
            index += 1
            count += 8
        }
        let value = accumulator & ((1 << width) - 1)
        accumulator >>= width
        count -= width
        return value
    }

    func align() {
        accumulator = 0
        count = 0
    }

    func bytes(_ length: Int) throws -> [UInt8] {
        align()
        guard length >= 0, index + length <= data.count else { throw ZipReadError.invalid }
        let slice = data.subdata(in: index..<(index + length))
        index += length
        return [UInt8](slice)
    }
}

enum PDFTextExtractor {
    static func string(from data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return document.string ?? ""
    }
}
