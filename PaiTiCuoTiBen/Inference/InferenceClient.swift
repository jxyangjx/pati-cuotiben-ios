import Foundation

/// Thin inference gateway.
///
/// `StubInferenceClient` stays on device. `HTTPInferenceClient` POSTs the text in these
/// requests to the paths in `InferencePath` and does not keep the payload.
/// Child profiles, page images, wrong-book rows, and per-question results stay in SwiftData.
protocol InferenceClient: Sendable {
    func solve(_ request: SolveRequest) async throws -> SolveResponse
    func grade(_ request: GradeRequest) async throws -> GradeResponse
    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse
    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup]
    func similar(_ request: SimilarQuestionRequest) async throws -> SimilarQuestionResponse
}
