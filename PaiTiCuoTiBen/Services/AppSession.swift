import SwiftUI

enum DefaultsKey {
    static let currentChildID = "currentChildID"
    static let lockThreshold = "lockThreshold"
    static let privacyConsentAccepted = "privacyConsentAccepted"
    static let inferenceMode = "inferenceMode"
    static let inferenceBaseURL = "inferenceBaseURL"
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
    private(set) var inference: any InferenceClient
    private(set) var inferenceMode: InferenceMode
    @Published var notice: String?

    init(inference: (any InferenceClient)? = nil) {
        if let inference {
            self.inference = inference
            self.inferenceMode = .stub
        } else {
            let resolved = InferenceClientFactory.make()
            self.inference = resolved.client
            self.inferenceMode = resolved.mode
        }
    }

    func reloadInference() {
        objectWillChange.send()
        let resolved = InferenceClientFactory.make()
        inference = resolved.client
        inferenceMode = resolved.mode
    }
}
