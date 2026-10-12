import XCTest
@testable import PaiTiCuoTiBen

final class DomainTests: XCTestCase {
    func testLockThresholdKeepsLowConfidencePending() {
        let decision = GradingPolicy.decide(
            student: "我觉得答案写在题干里",
            canonical: "（模拟标答）请核对本题最终答案",
            steps: ["低置信模拟步骤：确认前不会锁定对错，也不会进入错题本。"],
            questionType: "解答题",
            canonicalConfidence: 0.58,
            grade: GradeSignal(result: .wrong, confidence: 0.6, suggestedAuthority: .none),
            adoption: .none,
            verdictOverride: nil,
            userHoldPending: false
        )

        XCTAssertEqual(decision.canonicalConfirmation, .pending)
        XCTAssertEqual(decision.canonicalAuthority, .none)
        XCTAssertTrue(decision.stepsNeedReview)
        XCTAssertEqual(decision.verdict, .pending)
        XCTAssertFalse(decision.locked)
        XCTAssertFalse(decision.canEnterWrongBook)
        XCTAssertEqual(decision.leaning, .wrong)
    }

    func testObjectiveMismatchAutoLocksWrongBook() {
        let decision = GradingPolicy.decide(
            student: "3",
            canonical: "2",
            steps: ["1 加 1 得 2。"],
            questionType: "计算题",
            canonicalConfidence: 0.93,
            grade: GradeSignal(result: .wrong, confidence: 0.91, suggestedAuthority: .autoObjective),
            adoption: .none,
            verdictOverride: nil,
            userHoldPending: false
        )

        XCTAssertEqual(decision.canonicalConfirmation, .confirmed)
        XCTAssertEqual(decision.canonicalAuthority, .autoCanonical)
        XCTAssertFalse(decision.stepsNeedReview)
        XCTAssertEqual(decision.verdict, .wrong)
        XCTAssertEqual(decision.verdictAuthority, .autoObjective)
        XCTAssertTrue(decision.locked)
        XCTAssertTrue(decision.canEnterWrongBook)
    }

    func testObjectiveMatchDoesNotEnterWrongBook() {
        let decision = GradingPolicy.decide(
            student: "2",
            canonical: "2",
            steps: ["1 加 1 得 2。"],
            questionType: "计算题",
            canonicalConfidence: 0.93,
            grade: GradeSignal(result: .correct, confidence: 0.96, suggestedAuthority: .autoObjective),
            adoption: .none,
            verdictOverride: nil,
            userHoldPending: false
        )

        XCTAssertEqual(decision.verdict, .correct)
        XCTAssertTrue(decision.locked)
        XCTAssertFalse(decision.canEnterWrongBook)
    }

    func testUserCanConfirmAndMarkWrong() {
        let decision = GradingPolicy.decide(
            student: "我觉得答案写在题干里",
            canonical: "（模拟标答）请核对本题最终答案",
            steps: ["先写出已知条件。"],
            questionType: "解答题",
            canonicalConfidence: 0.58,
            grade: GradeSignal(result: .wrong, confidence: 0.6, suggestedAuthority: .none),
            adoption: .user,
            verdictOverride: .wrong,
            userHoldPending: false
        )

        XCTAssertEqual(decision.canonicalConfirmation, .confirmed)
        XCTAssertEqual(decision.canonicalAuthority, .userConfirm)
        XCTAssertEqual(decision.verdictAuthority, .userConfirm)
        XCTAssertTrue(decision.locked)
        XCTAssertTrue(decision.canEnterWrongBook)
        XCTAssertTrue(decision.stepsNeedReview)
    }

    func testHoldPendingBlocksAutomaticLock() {
        let decision = GradingPolicy.decide(
            student: "3",
            canonical: "2",
            steps: ["1 加 1 得 2。"],
            questionType: "计算题",
            canonicalConfidence: 0.93,
            grade: GradeSignal(result: .wrong, confidence: 0.91, suggestedAuthority: .autoObjective),
            adoption: .auto,
            verdictOverride: nil,
            userHoldPending: true
        )

        XCTAssertEqual(decision.canonicalConfirmation, .confirmed)
        XCTAssertEqual(decision.verdict, .pending)
        XCTAssertFalse(decision.locked)
        XCTAssertFalse(decision.canEnterWrongBook)
    }

    func testEmptyStepsCannotLock() {
        let decision = GradingPolicy.decide(
            student: "3",
            canonical: "2",
            steps: ["   "],
            questionType: "计算题",
            canonicalConfidence: 0.99,
            grade: GradeSignal(result: .wrong, confidence: 0.99, suggestedAuthority: .autoObjective),
            adoption: .user,
            verdictOverride: .wrong,
            userHoldPending: false
        )

        XCTAssertEqual(decision.canonicalConfirmation, .pending)
        XCTAssertFalse(decision.canEnterWrongBook)
    }

    func testRejectedAuthorities() {
        XCTAssertEqual(VerdictAuthority.resolve("teacher_key"), .none)
        XCTAssertEqual(VerdictAuthority.resolve("self_mark"), .none)
        XCTAssertEqual(VerdictAuthority.resolve("user_confirm"), .userConfirm)
        XCTAssertEqual(VerdictAuthority.resolve("auto_canonical"), .autoCanonical)
        XCTAssertEqual(VerdictAuthority.resolve("auto_objective"), .autoObjective)
    }

    func testChildLimitAndAnswerNormalization() {
        XCTAssertTrue(ChildPolicy.canActivate(activeCount: 4))
        XCTAssertFalse(ChildPolicy.canActivate(activeCount: 5))
        XCTAssertEqual(GradingPolicy.normalizeAnswer(" A　b "), "ab")
        XCTAssertEqual(AnalysisText.points([" 甲 ", "", "乙", "丙", "丁"]), ["甲", "乙", "丙"])
    }

    func testTeacherKeyFormatDetection() {
        XCTAssertEqual(TeacherKeyFormat.detect(filename: "答案.DOCX"), .docx)
        XCTAssertEqual(TeacherKeyFormat.detect(filename: "key.doc"), .doc)
        XCTAssertEqual(TeacherKeyFormat.detect(filename: "page.PNG"), .image)
        XCTAssertEqual(TeacherKeyFormat.detect(filename: "scan.pdf"), .pdf)
        XCTAssertEqual(TeacherKeyFormat.detect(filename: "notes.txt"), .unknown)
    }

    func testJSONListAndCanonicalSteps() {
        XCTAssertEqual(JSONList.decode(JSONList.encode(["甲", "乙"])), ["甲", "乙"])
        let canonical = CanonicalAnswer(text: "2", steps: ["一步"], explanation: "说明", confidence: 0.4)
        XCTAssertEqual(canonical.steps, ["一步"])
        canonical.steps = ["改过的步骤"]
        XCTAssertEqual(canonical.steps, ["改过的步骤"])
        let placeholder = CanonicalAnswer(text: "2", steps: [], explanation: "", confidence: 0.2)
        XCTAssertEqual(placeholder.steps, ["（步骤待补充）"])
    }

    func testStudentSnapshotPrefersConfirmedText() {
        let confirmed = Answer(rawOCR: "3", userConfirmed: "2")
        XCTAssertEqual(confirmed.snapshotText, "2")
        let blank = Answer(rawOCR: "3", userConfirmed: "  ")
        XCTAssertEqual(blank.snapshotText, "3")
    }

    func testZipArchiveAndChecksum() {
        XCTAssertEqual(CRC32.checksum(Data("hello".utf8)), 0x3610_A686)
        let archive = ZipStore.archive(entries: [
            ZipStore.Entry(name: "backup.json", data: Data("[]".utf8)),
        ])
        XCTAssertEqual([UInt8](archive.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertTrue(archive.range(of: Data("backup.json".utf8)) != nil)
        XCTAssertTrue(archive.range(of: Data([0x50, 0x4B, 0x01, 0x02])) != nil)
        XCTAssertEqual([UInt8](archive.suffix(22).prefix(4)), [0x50, 0x4B, 0x05, 0x06])
    }

    func testStubInferenceStaysDeterministic() async throws {
        let client = StubInferenceClient()
        let arithmetic = try await client.solve(
            SolveRequest(stemText: "计算：1 + 1 = ?", studentAnswer: "3", subject: "数学", grade: "七年级", teacherKeyFilename: "答案.docx")
        )
        XCTAssertEqual(arithmetic.text, "2")
        XCTAssertEqual(arithmetic.steps.count, 1)
        XCTAssertGreaterThanOrEqual(arithmetic.confidence, GradingPolicy.defaultLockThreshold)
        XCTAssertEqual(arithmetic.questionType, "计算题")
        XCTAssertEqual(arithmetic.sourceRefs, ["teacher-key:答案.docx"])

        let open = try await client.solve(
            SolveRequest(stemText: "说明题意", studentAnswer: "不知道", subject: "数学", grade: "七年级", teacherKeyFilename: nil)
        )
        XCTAssertLessThan(open.confidence, GradingPolicy.defaultLockThreshold)
        XCTAssertFalse(open.steps.isEmpty)
        XCTAssertTrue(open.sourceRefs.isEmpty)

        let empty = try await client.grade(
            GradeRequest(studentAnswer: " ", canonicalText: "2", questionType: "计算题", canonicalConfidence: 0.93)
        )
        XCTAssertEqual(empty.result, .pending)

        let analysis = try await client.errorAnalysis(
            ErrorAnalysisRequest(
                stemText: "1+1",
                studentAnswer: "3",
                canonicalText: "2",
                steps: ["1 加 1 得 2。"],
                questionType: "计算题",
                subject: "数学"
            )
        )
        XCTAssertGreaterThanOrEqual(analysis.points.count, 1)
        XCTAssertLessThanOrEqual(analysis.points.count, 3)
        XCTAssertFalse(analysis.avoidanceTips.isEmpty)

        let groups = try await client.summaryGroups(
            SummaryGroupsRequest(
                subject: "数学",
                grade: "七年级",
                questions: [
                    SummaryQuestionInput(questionType: "计算题", result: .wrong, stemText: "1"),
                    SummaryQuestionInput(questionType: "计算题", result: .pending, stemText: "2"),
                ]
            )
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].wrongCount, 1)
        XCTAssertEqual(groups[0].pendingCount, 1)
        XCTAssertEqual(groups[0].correctCount, 0)
    }
}
