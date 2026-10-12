import Foundation
import SwiftData

@Model
final class Question {
    var id: UUID
    var order: Int
    var pageID: UUID?
    var stemText: String
    var questionType: String
    var cropRelativePath: String?
    /// Normalized crop box reserved for the Vision milestone. Mock parse uses the full page.
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

    init(order: Int, pageID: UUID?, stemText: String, questionType: String) {
        self.id = UUID()
        self.order = order
        self.pageID = pageID
        self.stemText = stemText
        self.questionType = questionType
        self.cropRelativePath = nil
        self.cropX = 0
        self.cropY = 0
        self.cropWidth = 1
        self.cropHeight = 1
        self.job = nil
        self.answer = nil
        self.canonicalAnswer = nil
        self.verdict = nil
    }
}
