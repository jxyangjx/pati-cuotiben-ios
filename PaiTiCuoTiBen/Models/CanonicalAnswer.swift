import Foundation
import SwiftData

@Model
final class CanonicalAnswer {
    var text: String
    var stepsJSON: String
    var explanation: String
    var confirmationRaw: String
    var authorityRaw: String
    var confidence: Double
    var stepsNeedReview: Bool
    var sourceRefsJSON: String
    var question: Question?

    init(
        text: String,
        steps: [String],
        explanation: String,
        confidence: Double,
        sourceRefs: [String] = []
    ) {
        self.text = text
        self.stepsJSON = JSONList.encode(steps.isEmpty ? ["（步骤待补充）"] : steps)
        self.explanation = explanation
        self.confirmationRaw = CanonicalConfirmation.pending.rawValue
        self.authorityRaw = VerdictAuthority.none.rawValue
        self.confidence = confidence
        self.stepsNeedReview = confidence < GradingPolicy.defaultLockThreshold
        self.sourceRefsJSON = JSONList.encode(sourceRefs)
        self.question = nil
    }

    var steps: [String] {
        get { JSONList.decode(stepsJSON) }
        set { stepsJSON = JSONList.encode(newValue) }
    }

    var sourceRefs: [String] {
        get { JSONList.decode(sourceRefsJSON) }
        set { sourceRefsJSON = JSONList.encode(newValue) }
    }

    var confirmation: CanonicalConfirmation {
        get { CanonicalConfirmation.resolve(confirmationRaw) }
        set { confirmationRaw = newValue.rawValue }
    }

    var adoptedAuthority: VerdictAuthority {
        get { VerdictAuthority.resolve(authorityRaw) }
        set { authorityRaw = newValue.rawValue }
    }

    var adoption: CanonicalAdoption {
        guard confirmation == .confirmed else { return .none }
        return adoptedAuthority == .userConfirm ? .user : .auto
    }
}
