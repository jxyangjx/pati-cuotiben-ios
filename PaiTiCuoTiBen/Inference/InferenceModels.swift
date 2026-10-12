import Foundation

enum InferencePath {
    static let solve = "/v1/inference/solve"
    static let grade = "/v1/inference/grade"
    static let errorAnalysis = "/v1/inference/error-analysis"
    static let summaryGroups = "/v1/inference/summary-groups"
}

struct SolveRequest: Equatable, Sendable, Codable {
    var stemText: String
    var studentAnswer: String
    var subject: String
    var grade: String
    var teacherKeyFilename: String?
}

struct SolveResponse: Equatable, Sendable, Codable {
    var text: String
    var steps: [String]
    var explanation: String
    var questionType: String
    var confidence: Double
    var sourceRefs: [String]
}

struct GradeRequest: Equatable, Sendable, Codable {
    var studentAnswer: String
    var canonicalText: String
    var questionType: String
    var canonicalConfidence: Double
}

struct GradeResponse: Equatable, Sendable {
    var result: VerdictResult
    var confidence: Double
    var suggestedAuthority: VerdictAuthority
}

struct ErrorAnalysisRequest: Equatable, Sendable, Codable {
    var stemText: String
    var studentAnswer: String
    var canonicalText: String
    var steps: [String]
    var questionType: String
    var subject: String
}

struct ErrorAnalysisResponse: Equatable, Sendable, Codable {
    var points: [String]
    var avoidanceTips: [String]
}

struct SummaryQuestionInput: Equatable, Sendable, Codable {
    var questionType: String
    var result: VerdictResult
    var stemText: String
}

struct SummaryGroupsRequest: Equatable, Sendable, Codable {
    var subject: String
    var grade: String
    var questions: [SummaryQuestionInput]
}

struct SummaryGroup: Equatable, Sendable, Identifiable, Codable {
    var questionType: String
    var correctCount: Int
    var wrongCount: Int
    var pendingCount: Int
    var bullets: [String]

    var id: String { questionType }
}
