import UIKit
import XCTest
@testable import PaiTiCuoTiBen

@MainActor
final class JobPipelineTests: XCTestCase {
    private var container: ModelContainer?
    private var childIDs: [UUID] = []

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: DefaultsKey.privacyConsentAccepted)
    }

    override func tearDown() {
        for id in childIDs {
            SandboxStore.removeTree(relativePath: SandboxPath.childDirectory(childID: id))
        }
        childIDs = []
        container = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.privacyConsentAccepted)
        super.tearDown()
    }

    func testRecognizePagesSeparatesAutoWrongFromPending() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        XCTAssertEqual(job.mode, .a)
        XCTAssertEqual(job.sortedPages.first?.role, .questionSheet)
        XCTAssertEqual(job.status, .reviewing)
        XCTAssertEqual(job.sortedQuestions.count, 2)

        let arithmetic = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "计算题" })
        XCTAssertEqual(arithmetic.questionNumber, "1")
        XCTAssertNil(arithmetic.alignmentStatus)
        XCTAssertEqual(arithmetic.stemText, "1. 计算：1 + 1 = ?")
        XCTAssertEqual(arithmetic.stemRawOCR, arithmetic.stemText)
        XCTAssertGreaterThan(arithmetic.ocrConfidence, PrintedQuestionSegmenter.lowConfidenceThreshold)
        XCTAssertEqual(arithmetic.answer?.rawOCR, "3")
        XCTAssertFalse(arithmetic.stemText.contains("模拟"))
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
        XCTAssertEqual(item.errorTags, ["计算错误"])
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
        XCTAssertEqual(job.teacherKeyStatus, .failed)
        XCTAssertEqual(arithmetic.canonicalAnswer?.text, "2")
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
        let outcome = try await JobPipeline.recognizePages(
            job: job,
            context: context,
            inference: inference,
            threshold: GradingPolicy.defaultLockThreshold,
            recognizer: FixturePageTextRecognizer()
        )
        XCTAssertEqual(outcome.questionCount, 2)
        XCTAssertTrue(outcome.emptyPageNumbers.isEmpty)
        return job
    }

    func testEditedOCRTextResolvesAgain() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        let arithmetic = try XCTUnwrap(job.sortedQuestions.first { $0.questionType == "计算题" })
        arithmetic.stemText = "计算：1 + 1 = ?"
        arithmetic.answer?.userConfirmed = "2"
        try await JobPipeline.reprocessEditedText(
            question: arithmetic,
            job: job,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold
        )
        XCTAssertEqual(arithmetic.stemRawOCR, "1. 计算：1 + 1 = ?")
        XCTAssertEqual(arithmetic.answer?.snapshotText, "2")
        XCTAssertEqual(arithmetic.canonicalAnswer?.text, "2")
        XCTAssertEqual(arithmetic.verdict?.result, .correct)
        XCTAssertEqual(arithmetic.verdict?.locked, true)
    }

    func testEmptyOCRDoesNotEraseExistingCards() async throws {
        let context = try makeContext()
        let job = try await seedJob(context: context)
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context)
        let skipped = try await JobPipeline.recognizePages(
            job: job,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold,
            recognizer: SequentialRecognizer(pages: [FixtureLines.worksheet, []])
        )
        XCTAssertEqual(skipped.questionCount, 2)
        XCTAssertEqual(skipped.emptyPageNumbers, [2])
        XCTAssertEqual(job.sortedQuestions.count, 2)

        do {
            _ = try await JobPipeline.recognizePages(
                job: job,
                context: context,
                inference: StubInferenceClient(),
                threshold: GradingPolicy.defaultLockThreshold,
                recognizer: SequentialRecognizer(pages: [[], []])
            )
            XCTFail("Expected no printed text")
        } catch {
            XCTAssertEqual(error as? AppError, .noPrintedText)
        }
        XCTAssertEqual(job.sortedQuestions.count, 2)
    }

    func testModeBMatchesAnswerSheetAndKeepsFailuresPending() async throws {
        let context = try makeContext()
        let child = try JobPipeline.createChild(name: "小明", grade: .junior1, context: context)
        childIDs.append(child.id)
        let job = try JobPipeline.createDraft(
            child: child,
            grade: .junior1,
            subject: .math,
            answerContext: .student,
            context: context
        )
        try JobPipeline.setMode(job: job, mode: .b, context: context)
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context, role: .questionSheet)
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context, role: .answerSheet)
        let outcome = try await JobPipeline.recognizePages(
            job: job,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold,
            recognizer: SequentialRecognizer(pages: [
                [
                    OCRLine(text: "1. 计算：1 + 1 = ?", boundingBox: CGRect(x: 0.08, y: 0.72, width: 0.7, height: 0.08), confidence: 0.93),
                    OCRLine(text: "2. 用自己的话说明这道题在考什么。", boundingBox: CGRect(x: 0.08, y: 0.48, width: 0.8, height: 0.08), confidence: 0.9),
                ],
                [
                    OCRLine(text: "1. 3✓", boundingBox: CGRect(x: 0.08, y: 0.7, width: 0.3, height: 0.08), confidence: 0.91),
                    OCRLine(text: "2. 我觉得答案写在题干里", boundingBox: CGRect(x: 0.08, y: 0.4, width: 0.6, height: 0.08), confidence: 0.9),
                ],
            ])
        )
        XCTAssertEqual(outcome.questionCount, 2)
        XCTAssertEqual(job.alignmentSuccessCount, 2)
        XCTAssertEqual(job.alignmentFailureCount, 0)
        let arithmetic = try XCTUnwrap(job.sortedQuestions.first { $0.questionNumber == "1" })
        XCTAssertEqual(arithmetic.alignmentStatus, .matched)
        XCTAssertNil(arithmetic.alignmentCode)
        XCTAssertEqual(arithmetic.answer?.snapshotText, "3✓")
        XCTAssertEqual(arithmetic.answer?.markHints, MarkHints.unreliable)
        XCTAssertEqual(arithmetic.verdict?.authority, .autoObjective)
        XCTAssertNotEqual(arithmetic.verdict?.authorityRaw, "self_mark")
        XCTAssertEqual(arithmetic.verdict?.locked, true)
        let open = try XCTUnwrap(job.sortedQuestions.first { $0.questionNumber == "2" })
        XCTAssertEqual(open.alignmentStatus, .matched)
        XCTAssertEqual(open.verdict?.result, .pending)
        XCTAssertEqual(try wrongItems(in: context).count, 1)
    }

    func testModeBRealignAndTeacherDocxKeepSteps() async throws {
        let context = try makeContext()
        let child = try JobPipeline.createChild(name: "小明", grade: .junior1, context: context)
        childIDs.append(child.id)
        let job = try JobPipeline.createDraft(
            child: child,
            grade: .junior1,
            subject: .math,
            answerContext: .student,
            context: context
        )
        try JobPipeline.setMode(job: job, mode: .b, context: context)
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context, role: .questionSheet)
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context, role: .answerSheet)
        let xml = "<w:document><w:p><w:r><w:t>1. 9</w:t></w:r></w:p></w:document>"
        let docx = ZipStore.archive(entries: [
            ZipStore.Entry(name: "word/document.xml", data: Data(xml.utf8)),
        ])
        try JobPipeline.importTeacherKey(job: job, filename: "答案.docx", data: docx, context: context)
        XCTAssertEqual(job.teacherKeyStatus, .parsed)
        _ = try await JobPipeline.recognizePages(
            job: job,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold,
            recognizer: SequentialRecognizer(pages: [
                [OCRLine(text: "1. 计算：1 + 1 = ?", boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.6, height: 0.08), confidence: 0.95)],
                [OCRLine(text: "8. 多余", boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.4, height: 0.08), confidence: 0.9)],
            ])
        )
        let question = try XCTUnwrap(job.sortedQuestions.first { $0.questionNumber == "1" })
        XCTAssertEqual(question.alignmentCode, .missingAnswer)
        XCTAssertEqual(question.alignmentStatus, .failed)
        XCTAssertEqual(question.canonicalAnswer?.text, "9")
        XCTAssertEqual(question.canonicalAnswer?.steps, ["1 加 1 得 2。"])
        XCTAssertNotEqual(question.verdict?.authorityRaw, "teacher_key")
        XCTAssertEqual(question.verdict?.locked, false)
        XCTAssertTrue(try wrongItems(in: context).isEmpty)
        XCTAssertTrue(job.sortedQuestions.contains { $0.alignmentCode == .missingQuestion })

        question.answer?.userConfirmed = "3"
        try await JobPipeline.realign(
            job: job,
            context: context,
            inference: StubInferenceClient(),
            threshold: GradingPolicy.defaultLockThreshold
        )
        XCTAssertEqual(question.alignmentStatus, .matched)
        XCTAssertNil(question.alignmentCode)
        XCTAssertEqual(question.canonicalAnswer?.text, "9")
        XCTAssertEqual(question.canonicalAnswer?.steps, ["1 加 1 得 2。"])
        XCTAssertEqual(question.verdict?.result, .wrong)
        XCTAssertEqual(question.verdict?.locked, true)
        let before = try wrongItems(in: context).count
        let item = try XCTUnwrap(try wrongItems(in: context).first)
        let file = try await JobPipeline.generateSimilar(
            item: item,
            context: context,
            inference: StubInferenceClient(),
            locale: "zh-Hans"
        )
        XCTAssertEqual(file.items.count, 3)
        XCTAssertTrue(file.items.allSatisfy { $0.source == "generated" })
        XCTAssertEqual(item.similarCacheKey, SimilarCacheFile.key(wrongItemID: item.id, questionType: item.questionType, locale: "zh-Hans"))
        let again = try await JobPipeline.generateSimilar(
            item: item,
            context: context,
            inference: StubInferenceClient(),
            locale: "zh-Hans"
        )
        XCTAssertEqual(again.generatedAt, file.generatedAt)
        XCTAssertEqual(VariantPractice.check(attempt: "不是9", answer: file.items[0].answer), .incorrect)
        XCTAssertEqual(try wrongItems(in: context).count, before)
        try JobPipeline.setMode(job: job, mode: .a, context: context)
        XCTAssertTrue(job.pages.allSatisfy { $0.role == .questionSheet })
    }

    func testModeBRequiresBothPageRoles() async throws {
        let context = try makeContext()
        let child = try JobPipeline.createChild(name: "小明", grade: .junior1, context: context)
        childIDs.append(child.id)
        let job = try JobPipeline.createDraft(
            child: child,
            grade: .junior1,
            subject: .math,
            answerContext: .student,
            context: context
        )
        try JobPipeline.setMode(job: job, mode: .b, context: context)
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context, role: .questionSheet)
        do {
            _ = try await JobPipeline.recognizePages(
                job: job,
                context: context,
                inference: StubInferenceClient(),
                threshold: GradingPolicy.defaultLockThreshold,
                recognizer: FixturePageTextRecognizer()
            )
            XCTFail("Expected both roles")
        } catch {
            XCTAssertEqual(error as? AppError, .modeBNeedsBoth)
        }
        XCTAssertTrue(job.questions.isEmpty)
    }

    func testCreateChildAndRecognizeRequireConsent() async throws {
        UserDefaults.standard.set(false, forKey: DefaultsKey.privacyConsentAccepted)
        let context = try makeContext()
        XCTAssertThrowsError(try JobPipeline.createChild(name: "小明", grade: .junior1, context: context)) { error in
            XCTAssertEqual(error as? AppError, .privacyConsentRequired)
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.privacyConsentAccepted)
        let child = try JobPipeline.createChild(name: "小明", grade: .junior1, context: context)
        childIDs.append(child.id)
        let job = try JobPipeline.createDraft(
            child: child,
            grade: .junior1,
            subject: .math,
            answerContext: .student,
            context: context
        )
        try JobPipeline.addPage(job: job, imageData: tinyJPEG(), context: context)
        UserDefaults.standard.set(false, forKey: DefaultsKey.privacyConsentAccepted)
        do {
            _ = try await JobPipeline.recognizePages(
                job: job,
                context: context,
                inference: StubInferenceClient(),
                threshold: GradingPolicy.defaultLockThreshold,
                recognizer: FixturePageTextRecognizer()
            )
            XCTFail("Expected privacy consent")
        } catch {
            XCTAssertEqual(error as? AppError, .privacyConsentRequired)
        }
        XCTAssertTrue(job.questions.isEmpty)
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

enum FixtureLines {
    static let worksheet: [OCRLine] = [
        OCRLine(text: "1. 计算：1 + 1 = ?", boundingBox: CGRect(x: 0.08, y: 0.75, width: 0.70, height: 0.08), confidence: 0.92),
        OCRLine(text: "3", boundingBox: CGRect(x: 0.08, y: 0.62, width: 0.12, height: 0.06), confidence: 0.90),
        OCRLine(text: "2. 用自己的话说明这道题在考什么。", boundingBox: CGRect(x: 0.08, y: 0.45, width: 0.80, height: 0.08), confidence: 0.88),
        OCRLine(text: "我觉得答案写在题干里", boundingBox: CGRect(x: 0.08, y: 0.32, width: 0.55, height: 0.07), confidence: 0.86),
    ]
}

struct FixturePageTextRecognizer: PageTextRecognizing {
    func recognize(imageData: Data) async throws -> [OCRLine] {
        FixtureLines.worksheet
    }
}

final class SequentialRecognizer: PageTextRecognizing {
    private let pages: [[OCRLine]]
    private var index = 0

    init(pages: [[OCRLine]]) {
        self.pages = pages
    }

    func recognize(imageData: Data) async throws -> [OCRLine] {
        let lines = index < pages.count ? pages[index] : []
        index += 1
        return lines
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

    func similar(_ request: SimilarQuestionRequest) async throws -> SimilarQuestionResponse {
        try await StubInferenceClient().similar(request)
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

    func similar(_ request: SimilarQuestionRequest) async throws -> SimilarQuestionResponse {
        try await StubInferenceClient().similar(request)
    }
}
