import Foundation
import SwiftData

@Model
final class Verdict {
    var resultRaw: String
    var authorityRaw: String
    var confidence: Double
    var locked: Bool
    var leaningRaw: String?
    /// When true, a high-confidence objective grade stays pending until the user judges again.
    var holdPending: Bool
    var question: Question?

    init() {
        self.resultRaw = VerdictResult.pending.rawValue
        self.authorityRaw = VerdictAuthority.none.rawValue
        self.confidence = 0
        self.locked = false
        self.leaningRaw = nil
        self.holdPending = false
        self.question = nil
    }

    var result: VerdictResult {
        get { VerdictResult.resolve(resultRaw) }
        set { resultRaw = newValue.rawValue }
    }

    var authority: VerdictAuthority {
        get { VerdictAuthority.resolve(authorityRaw) }
        set { authorityRaw = newValue.rawValue }
    }

    var leaning: VerdictResult? {
        get { leaningRaw.flatMap { VerdictResult(rawValue: $0) } }
        set { leaningRaw = newValue?.rawValue }
    }
}
