import UIKit
import XCTest
@testable import PaiTiCuoTiBen

final class VisionOCRTests: XCTestCase {
    func testEmptyLinesProduceNoQuestions() {
        XCTAssertTrue(PrintedQuestionSegmenter.segment([]).isEmpty)
        let blank = OCRLine(text: "   ", boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.05), confidence: 0.4)
        XCTAssertTrue(PrintedQuestionSegmenter.segment([blank]).isEmpty)
    }

    func testNumberedLinesSplitAndLastLineIsTheAnswer() {
        let drafts = PrintedQuestionSegmenter.segment(FixtureLines.worksheet)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].stem, "1. 计算：1 + 1 = ?")
        XCTAssertEqual(drafts[0].studentAnswer, "3")
        XCTAssertEqual(drafts[0].confidence, 0.90)
        XCTAssertEqual(drafts[1].stem, "2. 用自己的话说明这道题在考什么。")
        XCTAssertEqual(drafts[1].studentAnswer, "我觉得答案写在题干里")
        XCTAssertLessThan(drafts[0].crop.minY, drafts[1].crop.minY)
    }

    func testSingleLineHasEmptyStudentAnswer() {
        let line = OCRLine(
            text: "1. 只有题干",
            boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.40, height: 0.10),
            confidence: 0.77
        )
        let drafts = PrintedQuestionSegmenter.segment([line])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].stem, "1. 只有题干")
        XCTAssertEqual(drafts[0].studentAnswer, "")
        XCTAssertEqual(drafts[0].crop.minX, 0.09, accuracy: 0.000_1)
        XCTAssertEqual(drafts[0].crop.minY, 0.29, accuracy: 0.000_1)
        XCTAssertEqual(drafts[0].crop.width, 0.42, accuracy: 0.000_1)
        XCTAssertEqual(drafts[0].crop.height, 0.12, accuracy: 0.000_1)
    }

    func testAdditionExpressionDoesNotStartAQuestion() {
        let lines = [
            OCRLine(text: "1. 填空", boundingBox: CGRect(x: 0.08, y: 0.80, width: 0.40, height: 0.06), confidence: 0.9),
            OCRLine(text: "1 + 1", boundingBox: CGRect(x: 0.08, y: 0.62, width: 0.30, height: 0.06), confidence: 0.9),
            OCRLine(text: "2. 下一题", boundingBox: CGRect(x: 0.08, y: 0.40, width: 0.40, height: 0.06), confidence: 0.8),
        ]
        let drafts = PrintedQuestionSegmenter.segment(lines)
        XCTAssertEqual(drafts.map(\.stem), ["1. 填空", "2. 下一题"])
        XCTAssertEqual(drafts.map(\.studentAnswer), ["1 + 1", ""])
    }

    func testReadingOrderAndSameLineJoin() {
        let reversed = [
            OCRLine(text: "3", boundingBox: CGRect(x: 0.10, y: 0.20, width: 0.10, height: 0.05), confidence: 0.7),
            OCRLine(text: "1. 先看这一题", boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.60, height: 0.06), confidence: 0.8),
        ]
        let ordered = PrintedQuestionSegmenter.segment(reversed)
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(ordered[0].stem, "1. 先看这一题")
        XCTAssertEqual(ordered[0].studentAnswer, "3")

        let sameLine = [
            OCRLine(text: "计算：1 + 1 = ?", boundingBox: CGRect(x: 0.25, y: 0.70, width: 0.50, height: 0.05), confidence: 0.81),
            OCRLine(text: "1.", boundingBox: CGRect(x: 0.08, y: 0.702, width: 0.08, height: 0.05), confidence: 0.95),
        ]
        let joined = PrintedQuestionSegmenter.segment(sameLine)
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].stem, "1. 计算：1 + 1 = ?")
        XCTAssertEqual(joined[0].studentAnswer, "")
        XCTAssertEqual(joined[0].confidence, 0.81)
    }

    func testChineseAndParenthesizedNumbers() {
        let lines = [
            OCRLine(text: "一、阅读下面的句子。", boundingBox: CGRect(x: 0.08, y: 0.80, width: 0.70, height: 0.06), confidence: 0.9),
            OCRLine(text: "春天来了", boundingBox: CGRect(x: 0.08, y: 0.68, width: 0.30, height: 0.06), confidence: 0.9),
            OCRLine(text: "（1）计算 2 + 2", boundingBox: CGRect(x: 0.08, y: 0.50, width: 0.50, height: 0.06), confidence: 0.4),
            OCRLine(text: "4", boundingBox: CGRect(x: 0.08, y: 0.36, width: 0.08, height: 0.05), confidence: 0.7),
        ]
        let drafts = PrintedQuestionSegmenter.segment(lines)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].stem, "一、阅读下面的句子。")
        XCTAssertEqual(drafts[0].studentAnswer, "春天来了")
        XCTAssertEqual(drafts[1].stem, "（1）计算 2 + 2")
        XCTAssertEqual(drafts[1].studentAnswer, "4")
        XCTAssertEqual(drafts[1].confidence, 0.4)
        XCTAssertLessThan(drafts[1].confidence, PrintedQuestionSegmenter.lowConfidenceThreshold)
    }

    func testVisionRecognizesPrintedArithmetic() async throws {
        let lines = try await VisionPageTextRecognizer().recognize(imageData: printedArithmeticJPEG())
        let joined = lines.map(\.text).joined()
        XCTAssertTrue(joined.contains("1"), "Vision returned: \(joined)")
    }

    private func printedArithmeticJPEG() -> Data {
        let size = CGSize(width: 1200, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "1 + 1 = 2" as NSString
            let font = UIFont.systemFont(ofSize: 140, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
            ]
            let bounds = text.size(withAttributes: attributes)
            let origin = CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2)
            text.draw(at: origin, withAttributes: attributes)
        }
        return image.jpegData(compressionQuality: 0.95) ?? Data()
    }
}
