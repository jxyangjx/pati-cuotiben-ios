import XCTest
@testable import PaiTiCuoTiBen

final class InferenceHTTPTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InferenceHTTPStub.self]
        session = URLSession(configuration: configuration)
        InferenceHTTPStub.handler = nil
    }

    override func tearDown() {
        InferenceHTTPStub.handler = nil
        session = nil
        super.tearDown()
    }

    func testPostsTextToTheFourGatewayPaths() async throws {
        let client = HTTPInferenceClient(
            baseURL: URL(string: "http://127.0.0.1:8787")!,
            apiKey: "gate-token",
            session: session
        )
        InferenceHTTPStub.handler = { request in
            let path = request.url?.path ?? ""
            let body = try Self.jsonObject(request)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gate-token")
            XCTAssertFalse(body.keys.contains { Self.forbiddenKeys.contains($0.lowercased()) })
            switch path {
            case InferencePath.solve:
                XCTAssertEqual(body["stem_text"] as? String, "计算：1 + 1 = ?")
                XCTAssertEqual(body["teacher_key_filename"] as? String, "答案.docx")
                return try Self.ok(request, object: [
                    "text": "2",
                    "steps": ["1 加 1 得 2。"],
                    "explanation": "加法",
                    "question_type": "计算题",
                    "confidence": 0.93,
                    "source_refs": ["teacher-key:答案.docx"],
                ])
            case InferencePath.grade:
                return try Self.ok(request, object: [
                    "result": "wrong",
                    "confidence": 0.91,
                    "suggested_authority": "teacher_key",
                ])
            case InferencePath.errorAnalysis:
                return try Self.ok(request, object: [
                    "points": ["进位错了"],
                    "avoidance_tips": ["先写竖式"],
                ])
            case InferencePath.summaryGroups:
                XCTAssertEqual((body["questions"] as? [Any])?.count, 1)
                return try Self.ok(request, object: [
                    "groups": [[
                        "question_type": "计算题",
                        "correct_count": 0,
                        "wrong_count": 1,
                        "pending_count": 0,
                        "bullets": ["共 1 题"],
                    ]],
                ])
            default:
                XCTFail("Unexpected path \(path)")
                return try Self.ok(request, object: [:])
            }
        }

        let solved = try await client.solve(
            SolveRequest(
                stemText: "计算：1 + 1 = ?",
                studentAnswer: "3",
                subject: "数学",
                grade: "七年级",
                teacherKeyFilename: "答案.docx"
            )
        )
        XCTAssertEqual(solved.text, "2")
        XCTAssertEqual(solved.questionType, "计算题")
        XCTAssertEqual(solved.sourceRefs, ["teacher-key:答案.docx"])

        let graded = try await client.grade(
            GradeRequest(studentAnswer: "3", canonicalText: "2", questionType: "计算题", canonicalConfidence: 0.93)
        )
        XCTAssertEqual(graded.result, .wrong)
        XCTAssertEqual(graded.suggestedAuthority, .none)

        let analysis = try await client.errorAnalysis(
            ErrorAnalysisRequest(
                stemText: "1+1",
                studentAnswer: "3",
                canonicalText: "2",
                steps: ["一步"],
                questionType: "计算题",
                subject: "数学"
            )
        )
        XCTAssertEqual(analysis.points, ["进位错了"])

        let groups = try await client.summaryGroups(
            SummaryGroupsRequest(
                subject: "数学",
                grade: "七年级",
                questions: [SummaryQuestionInput(questionType: "计算题", result: .wrong, stemText: "1 + 1")]
            )
        )
        XCTAssertEqual(groups.first?.wrongCount, 1)
        XCTAssertEqual(groups.first?.bullets, ["共 1 题"])
    }

    func testFailureStatusBecomesInferenceFailed() async {
        InferenceHTTPStub.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"error\":\"provider_failed\"}".utf8))
        }
        let client = HTTPInferenceClient(
            baseURL: URL(string: "http://127.0.0.1:8787/")!,
            apiKey: "",
            session: session
        )
        do {
            _ = try await client.solve(
                SolveRequest(stemText: "1+1", studentAnswer: "3", subject: "数学", grade: "七年级", teacherKeyFilename: nil)
            )
            XCTFail("Expected inference failure")
        } catch {
            XCTAssertEqual(error as? AppError, .inferenceFailed)
        }
    }

    func testFactoryDefaultsToStubAndLiveSelectsHTTP() async throws {
        let suite = "inference-factory-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let stubbed = InferenceClientFactory.make(defaults: defaults, bundle: Bundle.main)
        XCTAssertEqual(stubbed.mode, .stub)
        let solved = try await stubbed.client.solve(
            SolveRequest(stemText: "1 + 1", studentAnswer: "3", subject: "数学", grade: "七年级", teacherKeyFilename: nil)
        )
        XCTAssertEqual(solved.text, "2")

        defaults.set(InferenceMode.live.rawValue, forKey: DefaultsKey.inferenceMode)
        defaults.set("not a url", forKey: DefaultsKey.inferenceBaseURL)
        let unavailable = InferenceClientFactory.make(defaults: defaults, bundle: Bundle.main)
        XCTAssertTrue(unavailable.client is UnavailableInferenceClient)
        do {
            _ = try await unavailable.client.grade(
                GradeRequest(studentAnswer: "2", canonicalText: "2", questionType: "计算题", canonicalConfidence: 0.9)
            )
            XCTFail("Expected unavailable gateway")
        } catch {
            XCTAssertEqual(error as? AppError, .inferenceUnavailable)
        }

        defaults.set("http://127.0.0.1:8787", forKey: DefaultsKey.inferenceBaseURL)
        let live = InferenceClientFactory.make(defaults: defaults, bundle: Bundle.main)
        XCTAssertEqual(live.mode, .live)
        XCTAssertTrue(live.client is HTTPInferenceClient)
    }

    func testKeychainRoundTripUsesATestService() throws {
        let previous = InferenceKeychain.service
        InferenceKeychain.service = "app.paiticuotiben.ios.inference.tests"
        defer {
            InferenceKeychain.clear()
            InferenceKeychain.service = previous
        }
        InferenceKeychain.clear()
        XCTAssertFalse(InferenceKeychain.hasSecret)
        try InferenceKeychain.save("local-gateway-token")
        XCTAssertEqual(InferenceKeychain.load(), "local-gateway-token")
        try InferenceKeychain.save("   ")
        XCTAssertEqual(InferenceKeychain.load(), "")
    }

    func testSanitizedBuildSettingDropsUnsubstitutedValues() {
        XCTAssertEqual(InferenceConfig.sanitized("$(INFERENCE_API_KEY)"), "")
        XCTAssertEqual(InferenceConfig.sanitized("  http://127.0.0.1:8787  "), "http://127.0.0.1:8787")
    }

    private static let forbiddenKeys: Set<String> = [
        "image", "images", "image_base64", "image_url", "oss", "cos", "file_url", "page_image",
    ]

    private static func jsonObject(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody ?? request.collectedBody())
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private static func ok(_ request: URLRequest, object: [String: Any]) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        return (response, try JSONSerialization.data(withJSONObject: object))
    }
}

private extension URLRequest {
    func collectedBody() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class InferenceHTTPStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
