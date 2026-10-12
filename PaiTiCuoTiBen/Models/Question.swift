import CoreGraphics
import Foundation
import SwiftData

@Model
final class Question {
    var id: UUID
    var order: Int
    var pageID: UUID?
    var stemText: String
    /// Printed text as Vision returned it, before the user edits `stemText`.
    var stemRawOCR: String = ""
    /// Minimum line confidence for this question. `0` means unknown, including cards saved before OCR.
    var ocrConfidence: Double = 0
    var questionType: String
    var cropRelativePath: String?
    /// Normalized crop, origin at the top left. A full-page box is the fallback when the cut is unusable.
    var cropX: Double
    var cropY: Double
    var cropWidth: Double
    var cropHeight: Double
    var job: LocalJob?

    @Relationship(deleteRule: .cascade, inverse: \Answer.question)
    var answer: Answer?

    @Relationship(deleteRule: .cascade, inverse: \CanonicalAnswer.question)
    var canonicalAnswer: CanonicalAnswer?

    @Relationship(deleteRule: .cascade, inverse: \Verdict.question)
    var verdict: Verdict?

    init(
        order: Int,
        pageID: UUID?,
        stemText: String,
        questionType: String,
        stemRawOCR: String = "",
        ocrConfidence: Double = 0,
        crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) {
        self.id = UUID()
        self.order = order
        self.pageID = pageID
        self.stemText = stemText
        self.stemRawOCR = stemRawOCR
        self.ocrConfidence = ocrConfidence
        self.questionType = questionType
        self.cropRelativePath = nil
        self.cropX = crop.origin.x
        self.cropY = crop.origin.y
        self.cropWidth = crop.width
        self.cropHeight = crop.height
        self.job = nil
        self.answer = nil
        self.canonicalAnswer = nil
        self.verdict = nil
    }
}
