import UIKit
import XCTest
@testable import PaiTiCuoTiBen

@MainActor
final class JobPipelineTests: XCTestCase {
    private var container: ModelContainer?
    private var childIDs: [UUID] = []

    override func tearDown() {
        for id in childIDs {
            SandboxStore.removeTree(relativePath: SandboxPath.childDirectory(childID: id))
        }
        childIDs = []
        container = nil
        super.tearDown()
    }

    func testMockParseSeparatesAutoWrongFromPending() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        XCTAssertEqual(job.mode, .a)
        XCTAssertEqual(job.status, .reviewing)
        XCTAssertEqual(job.sortedQuestions.count, 2)

        let arithmetic = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "计算题" })
        XCTAssertEqual(arithmetic.canonicalAnswer?.text, "2")
        XCTAssertEqual(arithmetic.canonicalAnswer?.steps, ["1 加 1 得 2。"])
        XCTAssertEqual(arithmetic.canonicalAnswer?.confirmation, .confirmed)
        XCTAssertEqual(arithmetic.verdict?.result, .wrong)
        XCTAssertEqual(arithmetic.verdict?.authority, .autoObjective)
        XCTAssertEqual(arithmetic.verdict?.locked, true)

        let open = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "解答题" })
        XCTAssertEqual(open.verdict?.result, .pending)
        XCTAssertEqual(open.verdict?.locked, false)
        XCTAssertEqual(open.canonicalAnswer?.confirmation, .pending)

        let wrongItems = try wrongItems(in: context)
        XCTAssertEqual(wrongItems.count, 1)
        let item = try XCTUnwrap(wrongItems.first)
        XCTAssertEqual(item.studentAnswerText, "3")
        XCTAssertEqual(item.canonicalText, "2")
        XCTAssertEqual(item.canonicalSteps, ["1 加 1 得 2。"])
        XCTAssertEqual(item.analysisStatus, .ready)
        XCTAssertFalse(item.points.isEmpty)
        XCTAssertLessThanOrEqual(item.points.count, 3)
        XCTAssertFalse(item.avoidanceTips.isEmpty)
        XCTAssertTrue(SandboxStore.fileExists(relativePath: item.cropRelativePath))
    }

    func testSelfMarkAndTeacherKeyDoNotBecomeAuthority() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context, answerContext: .selfMark, teacherFilename: "答案.docx")
        let arithmetic = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "计算题" })
        XCTAssertEqual(arithmetic.answer?.markHints, "疑似已批，自批痕迹不可靠")
        XCTAssertEqual(arithmetic.verdict?.authority, .autoObjective)
        XCTAssertNotEqual(arithmetic.verdict?.authorityRaw, "teacher_key")
        XCTAssertNotEqual(arithmetic.verdict?.authorityRaw, "self_mark")
        XCTAssertEqual(arithmetic.canonicalAnswer?.sourceRefs, ["teacher-key:答案.docx"])
        XCTAssertNotEqual(arithmetic.canonicalAnswer?.authorityRaw, "teacher_key")
    }

    func testUserMarkWrongEntersBookAndCorrectRemovesIt() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        let open = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "解答题" })
        try await JobPipeline.judge(
            question: open,
            job: job,
            result: .wrong,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold
        )

        var items = try wrongItems(in: context)
        XCTAssertEqual(items.count, 2)
        let created = try XCTUnwrap(items.first { $0.sourceQuestionID == open.id })
        XCTAssertEqual(created.studentAnswerText, "我觉得答案写在题干里")
        XCTAssertFalse(created.canonicalSteps.isEmpty)
        XCTAssertEqual(created.analysisStatus, .ready)

        try await JobPipeline.judge(
            question: open,
            job: job,
            result: .correct,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold
        )
        items = try wrongItems(in: context)
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items.contains { $0.sourceQuestionID == open.id })
    }

    func testReopenRemovesWrongItemUntilJudgedAgain() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        let arithmetic = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "计算题" })
        try await JobPipeline.judge(
            question: arithmetic,
            job: job,
            result: .pending,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold
        )
        XCTAssertEqual(arithmetic.verdict?.result, .pending)
        XCTAssertEqual(arithmetic.verdict?.holdPending, true)
        XCTAssertTrue(try wrongItems(in: context).isEmpty)
    }

    func testSwitchClearsDraftsOnly() async throws {
        let context = try makeContext()
        let reviewed = try await seedJob(context: context)
        let child = try XCTUnwrap(reviewed.child)
        _ = try JobPipeline.createDraft(
            child: child,
            grade: .junior1,
            subject: .chinese,
            answerContext: .student,
            context: context
        )
        let removed = try JobPipeline.clearDrafts(context: context)
        XCTAssertEqual(removed, 1)
        let remaining = try context.fetch(FetchDescriptor<LocalJob>())
        XCTAssertEqual(remaining.map(\.id), [reviewed.id])
        XCTAssertEqual(remaining.first?.status, .reviewing)
    }

    func testActiveChildLimit() throws {
        let context = try makeContext()
        for index in 1...5 {
            let child = try JobPipeline.createChild(name: "孩子\(index)", grade: .primary6, context: context)
            childIDs.append(child.id)
        }
        XCTAssertThrowsError(try JobPipeline.createChild(name: "第六个", grade: .primary6, context: context)) { error in
            XCTAssertEqual(error as? AppError, .childLimit)
        }
    }

    func testAnalysisFailureKeepsTheWrongItem() async throws {
        let context = try makeContext()
        _ = try await seedJob(context: context, inference: ThrowingAnalysis())
        let failed = try XCTUnwrap(try wrongItems(in: context).first)
        XCTAssertEqual(failed.analysisStatus, .failed)
        XCTAssertEqual(failed.canonicalText, "2")
        XCTAssertEqual(failed.studentAnswerText, "3")
    }

    func testAnalysisPointsClampToThree() async throws {
        let context = try makeContext()
        _ = try await seedJob(context: context, inference: ClampedAnalysis())
        let clamped = try XCTUnwrap(try wrongItems(in: context).first)
        XCTAssertEqual(clamped.analysisStatus, .ready)
        XCTAssertEqual(clamped.points, ["1", "2", "3"])
        XCTAssertEqual(clamped.avoidanceTips, ["只留一条"])
    }

    func testPurgeKeepsWrongCrop() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        let page = try XCTUnwrap(job.sortedPages.first)
        page.createdAt = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        try context.save()
        let removed = try JobPipeline.purgeOriginals(olderThan: 30, context: context)
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(page.purged)
        XCTAssertFalse(SandboxStore.fileExists(relativePath: page.imageRelativePath))
        let item = try XCTUnwrap(try wrongItems(in: context).first)
        XCTAssertTrue(SandboxStore.fileExists(relativePath: item.cropRelativePath))
    }

    func testBackupPackageContainsManifest() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        let child = try XCTUnwrap(job.child)
        let url = try BackupExporter.makePackage(
            children: [child],
            jobs: [job],
            wrongItems: try wrongItems(in: context)
        )
        let data = try Data(contentsOf: url)
        XCTAssertEqual([UInt8](data.prefix(2)), [0x50, 0x4B])
        XCTAssertNotNil(data.range(of: Data("backup.json".utf8)))
        XCTAssertNotNil(data.range(of: Data("paiticuotiben.backup".utf8)))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        self.container = container
        return ModelContext(container)
    }

    private func seedJob(
        context: ModelContext,
        answerContext: AnswerContext = .student,
        teacherFilename: String? = nil,
        inference: any InferenceClient = StubInferenceClient()
    ) async throws -> LocalJob {
        let child = try JobPipeline.createChild(name: "小明", grade: .junior1, context: context)
        childIDs.append(child.id)
        let job = try JobPipeline.createDraft(
            child: child,
            grade: .junior1,
            subject: .math,
            answerContext: answerContext,
            context: context
        )
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context)
        if let teacherFilename {
            try JobPipeline.importTeacherKey(
                job: job,
                filename: teacherFilename,
                data: Data("teacher".utf8),
                context: context
            )
        }
        try await JobPipeline.mockParse(
            job: job,
            context: context,
            inference: inference,
            threshold: GradingPolicy.defaultLockThreshold
        )
        return job
    }

    private func wrongItems(in context: ModelContext) throws -> [WrongItem] {
        try context.fetch(FetchDescriptor<WrongItem>())
    }

    private func tinyJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

private struct ThrowingAnalysis: InferenceClient {
    func solve(_ request: SolveRequest) async throws -> SolveResponse {
        try await StubInferenceClient().solve(request)
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        try await StubInferenceClient().grade(request)
    }

    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse {
        throw AppError.missingCanonical
    }

    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup] {
        try await StubInferenceClient().summaryGroups(request)
    }
}

private struct ClampedAnalysis: InferenceClient {
    func solve(_ request: SolveRequest) async throws -> SolveResponse {
        try await StubInferenceClient().solve(request)
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        try await StubInferenceClient().grade(request)
    }

    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse {
        ErrorAnalysisResponse(points: ["1", "2", "3", "4", "5"], avoidanceTips: ["只留一条"])
    }

    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup] {
        []
    }
}
