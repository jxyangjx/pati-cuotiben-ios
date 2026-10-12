import SwiftUI

enum DefaultsKey {
    static let currentChildID = "currentChildID"
    static let lockThreshold = "lockThreshold"
}

@MainActor
final class AppSession: ObservableObject {
    let inference: any InferenceClient
    @Published var notice: String?

    init(inference: any InferenceClient = StubInferenceClient()) {
        self.inference = inference
    }
}
