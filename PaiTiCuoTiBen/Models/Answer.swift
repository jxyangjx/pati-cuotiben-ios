import Foundation
import SwiftData

@Model
final class Answer {
    var rawOCR: String
    var userConfirmed: String?
    /// Weak hint such as "疑似已批". Never an authority.
    var markHints: String?
    var question: Question?

    init(rawOCR: String, userConfirmed: String? = nil, markHints: String? = nil) {
        self.rawOCR = rawOCR
        self.userConfirmed = userConfirmed
        self.markHints = markHints
        self.question = nil
    }

    /// `user_confirmed ?? raw_ocr`, treating blank confirmation as absent.
    var snapshotText: String {
        if let userConfirmed {
            let trimmed = userConfirmed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return rawOCR
    }
}
