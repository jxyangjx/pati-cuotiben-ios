import Foundation

enum InferencePath {
    static let solve = "/v1/inference/solve"
    static let grade = "/v1/inference/grade"
    static let errorAnalysis = "/v1/inference/error-analysis"
    static let summaryGroups = "/v1/inference/summary-groups"
    static let similar = "/v1/inference/similar"
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
    var tags: [String]

    init(points: [String], avoidanceTips: [String], tags: [String] = []) {
        self.points = points
        self.avoidanceTips = avoidanceTips
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case avoidanceTips
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode([String].self, forKey: .points)
        avoidanceTips = try container.decode([String].self, forKey: .avoidanceTips)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
        try container.encode(avoidanceTips, forKey: .avoidanceTips)
        try container.encode(tags, forKey: .tags)
    }
}

struct SimilarQuestionRequest: Equatable, Sendable, Codable {
    var stemText: String
    var canonicalText: String
    var questionType: String
    var subject: String
    var locale: String
}

struct SimilarQuestionItem: Equatable, Sendable, Codable {
    var stem: String
    var answer: String?
    var source: String
}

struct SimilarQuestionResponse: Equatable, Sendable, Codable {
    var items: [SimilarQuestionItem]
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
