import Foundation

/// POSTs question text to the local inference gateway and drops the payload after the call.
struct HTTPInferenceClient: InferenceClient {
    var baseURL: URL
    var apiKey: String
    var session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func solve(_ request: SolveRequest) async throws -> SolveResponse {
        try await post(InferencePath.solve, body: request, as: SolveResponse.self)
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        let wire = try await post(InferencePath.grade, body: request, as: GradeWire.self)
        return GradeResponse(
            result: VerdictResult.resolve(wire.result),
            confidence: wire.confidence,
            suggestedAuthority: VerdictAuthority.resolve(wire.suggestedAuthority)
        )
    }

    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse {
        try await post(InferencePath.errorAnalysis, body: request, as: ErrorAnalysisResponse.self)
    }

    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup] {
        let envelope = try await post(InferencePath.summaryGroups, body: request, as: SummaryEnvelope.self)
        return envelope.groups
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        as responseType: Response.Type
    ) async throws -> Response {
        guard let url = InferenceConfig.endpoint(baseURL, path: path) else {
            throw AppError.inferenceUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.inferenceFailed
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw AppError.inferenceFailed
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AppError.inferenceFailed
        }
    }
}

struct UnavailableInferenceClient: InferenceClient {
    func solve(_ request: SolveRequest) async throws -> SolveResponse {
        throw AppError.inferenceUnavailable
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        throw AppError.inferenceUnavailable
    }

    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse {
        throw AppError.inferenceUnavailable
    }

    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup] {
        throw AppError.inferenceUnavailable
    }
}

private struct GradeWire: Decodable {
    var result: String
    var confidence: Double
    var suggestedAuthority: String
}

private struct SummaryEnvelope: Decodable {
    var groups: [SummaryGroup]
}
