import Foundation

/// Thin inference gateway.
///
/// Phase 1 ships `StubInferenceClient`, which stays on device.
/// A later client may POST cropped text to the paths in `InferencePath` and must discard the payload after the call.
/// Child profiles, wrong-book rows, and per-question results stay in SwiftData.
protocol InferenceClient: Sendable {
    func solve(_ request: SolveRequest) async throws -> SolveResponse
    func grade(_ request: GradeRequest) async throws -> GradeResponse
    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse
    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup]
}
