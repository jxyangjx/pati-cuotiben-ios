import Foundation

struct GradeSignal: Equatable {
    var result: VerdictResult
    var confidence: Double
    var suggestedAuthority: VerdictAuthority
}

struct GradingDecision: Equatable {
    var canonicalConfirmation: CanonicalConfirmation
    var canonicalAuthority: VerdictAuthority
    var stepsNeedReview: Bool
    var verdict: VerdictResult
    var verdictAuthority: VerdictAuthority
    var verdictConfidence: Double
    var locked: Bool
    var leaning: VerdictResult?

    var canEnterWrongBook: Bool {
        locked && verdict == .wrong && canonicalConfirmation == .confirmed
    }
}

enum GradingPolicy {
    static let defaultLockThreshold = 0.85

    static func normalizeAnswer(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .lowercased()
    }

    static func looksObjective(canonical: String, questionType: String) -> Bool {
        let trimmed = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12 else { return false }
        switch questionType {
        case "选择题", "填空题", "计算题":
            return true
        default:
            break
        }
        if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return true
            }
        }
        return trimmed.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" || $0 == "/" }
    }

    static func decide(
        student: String,
        canonical: String,
        steps: [String],
        questionType: String,
        canonicalConfidence: Double,
        grade: GradeSignal,
        adoption: CanonicalAdoption,
        verdictOverride: VerdictResult?,
        userHoldPending: Bool,
        suppressAutoLock: Bool = false,
        threshold: Double = defaultLockThreshold
    ) -> GradingDecision {
        let canonicalText = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableSteps = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasCanonical = !canonicalText.isEmpty && !usableSteps.isEmpty
        let highCanonical = hasCanonical && canonicalConfidence >= threshold
        let stepsNeedReview = usableSteps.isEmpty || canonicalConfidence < threshold

        let confirmation: CanonicalConfirmation
        let canonicalAuthority: VerdictAuthority
        if !hasCanonical {
            confirmation = .pending
            canonicalAuthority = .none
        } else {
            switch adoption {
            case .user:
                confirmation = .confirmed
                canonicalAuthority = .userConfirm
            case .auto, .none:
                if highCanonical {
                    confirmation = .confirmed
                    canonicalAuthority = .autoCanonical
                } else {
                    confirmation = .pending
                    canonicalAuthority = .none
                }
            }
        }

        if let verdictOverride, verdictOverride != .pending, confirmation == .confirmed {
            return GradingDecision(
                canonicalConfirmation: confirmation,
                canonicalAuthority: canonicalAuthority,
                stepsNeedReview: stepsNeedReview,
                verdict: verdictOverride,
                verdictAuthority: .userConfirm,
                verdictConfidence: 1,
                locked: true,
                leaning: nil
            )
        }

        let studentEmpty = normalizeAnswer(student).isEmpty
        let objective = looksObjective(canonical: canonicalText, questionType: questionType)
        let suggestedCanLock = grade.suggestedAuthority == .autoObjective || grade.suggestedAuthority == .autoCanonical
        let modelAgreesToLock = confirmation == .confirmed
            && !stepsNeedReview
            && !studentEmpty
            && !userHoldPending
            && !suppressAutoLock
            && grade.result != .pending
            && grade.confidence >= threshold
            && suggestedCanLock
            && objective

        if modelAgreesToLock {
            return GradingDecision(
                canonicalConfirmation: confirmation,
                canonicalAuthority: canonicalAuthority,
                stepsNeedReview: stepsNeedReview,
                verdict: grade.result,
                verdictAuthority: grade.suggestedAuthority,
                verdictConfidence: grade.confidence,
                locked: true,
                leaning: nil
            )
        }

        let leaning: VerdictResult? = grade.result == .pending ? nil : grade.result
        return GradingDecision(
            canonicalConfirmation: confirmation,
            canonicalAuthority: canonicalAuthority,
            stepsNeedReview: stepsNeedReview,
            verdict: .pending,
            verdictAuthority: .none,
            verdictConfidence: grade.confidence,
            locked: false,
            leaning: leaning
        )
    }
}
