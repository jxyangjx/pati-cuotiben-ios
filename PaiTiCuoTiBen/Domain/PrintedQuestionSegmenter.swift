import CoreGraphics
import Foundation

/// One printed-text line from Vision. `boundingBox` uses Vision's normalized space: origin at the bottom left.
struct OCRLine: Equatable, Sendable {
    var text: String
    var boundingBox: CGRect
    var confidence: Double
}

/// A Mode A question cut from printed lines. `crop` is normalized with the origin at the top left.
struct QuestionDraft: Equatable, Sendable {
    var stem: String
    var studentAnswer: String
    var crop: CGRect
    var confidence: Double
}

/// Groups printed OCR lines into question drafts. The last line of a multi-line block is the student answer.
enum PrintedQuestionSegmenter {
    static let lowConfidenceThreshold = 0.5
    static let sameLineThreshold: CGFloat = 0.015
    static let cropPadding: CGFloat = 0.01

    static func segment(_ lines: [OCRLine]) -> [QuestionDraft] {
        let rows = readingRows(from: lines)
        guard !rows.isEmpty else { return [] }

        var blocks: [[ReadingRow]] = []
        var current: [ReadingRow] = []
        for row in rows {
            if isQuestionStart(row.text), !current.isEmpty {
                blocks.append(current)
                current = [row]
            } else {
                current.append(row)
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }
        return blocks.compactMap(draft(from:))
    }

    private struct ReadingRow {
        var text: String
        var boxes: [CGRect]
        var confidence: Double
    }

    private static func readingRows(from lines: [OCRLine]) -> [ReadingRow] {
        let cleaned = lines.compactMap { line -> OCRLine? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var copy = line
            copy.text = text
            return copy
        }
        let sorted = cleaned.sorted { lhs, rhs in
            if lhs.boundingBox.maxY != rhs.boundingBox.maxY {
                return lhs.boundingBox.maxY > rhs.boundingBox.maxY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var grouped: [[OCRLine]] = []
        for line in sorted {
            if let anchor = grouped.last?.first,
               abs(anchor.boundingBox.maxY - line.boundingBox.maxY) <= sameLineThreshold {
                grouped[grouped.count - 1].append(line)
                grouped[grouped.count - 1].sort { $0.boundingBox.minX < $1.boundingBox.minX }
            } else {
                grouped.append([line])
            }
        }

        return grouped.map { group in
            let text = group
                .map(\.text)
                .joined(separator: " ")
            let confidence = group.map(\.confidence).min() ?? 0
            return ReadingRow(text: text, boxes: group.map(\.boundingBox), confidence: confidence)
        }
    }

    /// Numbered worksheet markers start a question. `1 + 1` does not, because the gap is not a delimiter.
    private static func isQuestionStart(_ text: String) -> Bool {
        let pattern = #"^\s*(?:\d{1,3}[.、．)）]|[（(]\d{1,3}[）)]|[一二三四五六七八九十]+[、.．])\s*\S"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func draft(from rows: [ReadingRow]) -> QuestionDraft? {
        let texts = rows.map(\.text).filter { !$0.isEmpty }
        guard let first = texts.first else { return nil }
        let stem: String
        let student: String
        if texts.count == 1 {
            stem = first
            student = ""
        } else {
            stem = texts.dropLast().joined(separator: "\n")
            student = texts.last ?? ""
        }
        let boxes = rows.flatMap(\.boxes)
        let confidence = rows.map(\.confidence).min() ?? 0
        return QuestionDraft(
            stem: stem,
            studentAnswer: student,
            crop: topLeftCrop(from: boxes),
            confidence: confidence
        )
    }

    /// Converts a union of Vision boxes into a padded, clamped top-left crop.
    static func topLeftCrop(from boxes: [CGRect]) -> CGRect {
        guard !boxes.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let minX = boxes.map(\.minX).min() ?? 0
        let maxX = boxes.map(\.maxX).max() ?? 1
        let minY = boxes.map(\.minY).min() ?? 0
        let maxY = boxes.map(\.maxY).max() ?? 1
        let top = 1 - maxY
        let height = maxY - minY
        let expanded = CGRect(
            x: minX - cropPadding,
            y: top - cropPadding,
            width: (maxX - minX) + cropPadding * 2,
            height: height + cropPadding * 2
        )
        return clampUnit(expanded)
    }

    static func clampUnit(_ rect: CGRect) -> CGRect {
        let minX = min(max(rect.minX, 0), 1)
        let minY = min(max(rect.minY, 0), 1)
        let maxX = min(max(rect.maxX, 0), 1)
        let maxY = min(max(rect.maxY, 0), 1)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
