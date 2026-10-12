import SwiftUI

enum DefaultsKey {
    static let currentChildID = "currentChildID"
    static let lockThreshold = "lockThreshold"
    static let privacyConsentAccepted = "privacyConsentAccepted"
}

enum PrivacyConsent {
    static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.privacyConsentAccepted)
    }

    static func require() throws {
        guard isAccepted else { throw AppError.privacyConsentRequired }
    }
}

@MainActor
final class AppSession: ObservableObject {
    let inference: any InferenceClient
    @Published var notice: String?

    init(inference: any InferenceClient = StubInferenceClient()) {
        self.inference = inference
    }
}
