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
        let cleared = Answer(rawOCR: "3", userConfirmed: "  ")
        XCTAssertEqual(cleared.snapshotText, "")
        let untouched = Answer(rawOCR: "3", userConfirmed: nil)
        XCTAssertEqual(untouched.snapshotText, "3")
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
        XCTAssertEqual(analysis.tags, ["计算错误"])

        let variants = try await client.similar(
            SimilarQuestionRequest(
                stemText: "计算：1 + 1 = ?",
                canonicalText: "2",
                questionType: "计算题",
                subject: "数学",
                locale: "zh-Hans"
            )
        )
        XCTAssertGreaterThanOrEqual(variants.items.count, 2)
        XCTAssertLessThanOrEqual(variants.items.count, 3)
        XCTAssertTrue(variants.items.allSatisfy { $0.source == "generated" })
    }

    func testAlignmentFailureDoesNotAutoLock() {
        let decision = GradingPolicy.decide(
            student: "3",
            canonical: "2",
            steps: ["1 加 1 得 2。"],
            questionType: "计算题",
            canonicalConfidence: 0.93,
            grade: GradeSignal(result: .wrong, confidence: 0.91, suggestedAuthority: .autoObjective),
            adoption: .none,
            verdictOverride: nil,
            userHoldPending: false,
            suppressAutoLock: true
        )
        XCTAssertEqual(decision.verdict, .pending)
        XCTAssertFalse(decision.locked)
        XCTAssertFalse(decision.canEnterWrongBook)
        XCTAssertEqual(decision.verdictAuthority, .none)
    }

    func testModeBAlignmentCodes() {
        let questions = [
            segment("1. 计算：1 + 1 = ?", page: 1),
            segment("2. 说明题意", page: 1),
            segment("2. 另一道题", page: 1),
            segment("没有题号的一行", page: 1),
        ]
        let answers = [
            answer("1. 3✓", page: 2),
            answer("4. B", page: 2),
            answer("4. C", page: 2),
        ]
        let aligned = SheetAligner.align(questions: questions, answers: answers)
        let matched = aligned.first { $0.questionNumber == "1" && $0.status == .matched }
        XCTAssertEqual(matched?.studentAnswer, "3✓")
        XCTAssertEqual(matched?.markHint, MarkHints.unreliable)
        XCTAssertEqual(matched?.code, nil)
        XCTAssertEqual(aligned.filter { $0.code == .ambiguousNumber }.count, 4)
        XCTAssertTrue(aligned.contains { $0.code == .missingQuestion && $0.questionNumber == "4" || $0.code == .ambiguousNumber && $0.questionNumber == "4" })
        XCTAssertTrue(aligned.contains { $0.code == .unreadable })
        XCTAssertFalse(aligned.contains { $0.status == .matched && $0.questionNumber == "2" })

        let repaired = SheetAligner.realign([
            RealignCard(number: "1", stem: "1. 计算：1 + 1 = ?", answer: "3", origin: .questionSheet),
            RealignCard(number: "2", stem: AlignmentCopy.missingQuestionStem, answer: "B", origin: .answerSheet),
            RealignCard(number: "1", stem: "重复", answer: "4", origin: .questionSheet),
        ])
        XCTAssertEqual(repaired[0].code, .ambiguousNumber)
        XCTAssertEqual(repaired[1].code, .missingQuestion)
        XCTAssertEqual(repaired[2].code, .ambiguousNumber)

        let unique = SheetAligner.realign([
            RealignCard(number: "01", stem: "1. 计算：1 + 1 = ?", answer: "3", origin: .both),
        ])
        XCTAssertEqual(unique[0].status, .matched)
        XCTAssertNil(unique[0].code)
    }

    func testTeacherDocxAlignsFinalAnswerOnly() throws {
        let stored = ZipStore.archive(entries: [
            ZipStore.Entry(
                name: "word/document.xml",
                data: Data(
                    """
                    <w:document><w:p><w:r><w:t>1. 9</w:t></w:r></w:p><w:p><w:r><w:t>步骤不要拿来当答案</w:t></w:r></w:p></w:document>
                    """.utf8
                )
            ),
        ])
        let parsed = TeacherKeyText.inspect(format: .docx, data: stored)
        XCTAssertEqual(parsed.status, .parsed)
        let answers = TeacherAnswerAligner.map(from: parsed.text)
        XCTAssertEqual(answers["1"], "9\n步骤不要拿来当答案")
        let text = TeacherAnswerAligner.alignedText(
            systemText: "2",
            questionNumber: "1",
            answers: answers,
            plainText: parsed.text,
            soleQuestion: false
        )
        XCTAssertEqual(text, "9\n步骤不要拿来当答案")
        let steps = ["1 加 1 得 2。"]
        XCTAssertEqual(steps, ["1 加 1 得 2。"])

        let deflated = Data(hex: """
        504b03041400000008003d174d5dff18e6d5690000008500000011000000776f72642f646f63756d656e742e786d6c35cd5d0a83301004e0ab8807706d1f0a0d69ee1262aa82fbc3ee96f4f835425f3e669887892d2c5c3e58c9872f1e64a1bdc6cd5d028095ad62b689a5d2b9bd5931fb597585c6ba8872a9663bad78c07d9e1f8079a731c516a4a31d4fb7697846e8a9ab9772f93f4e3f504b010214031400000008003d174d5dff18e6d56900000085000000110000000000000000000000800100000000776f72642f646f63756d656e742e786d6c504b050600000000010001003f000000980000000000
        """)
        let inflated = TeacherKeyText.inspect(format: .docx, data: deflated)
        XCTAssertEqual(inflated.status, .parsed)
        XCTAssertEqual(TeacherAnswerAligner.map(from: inflated.text)["1"], "9")

        let legacy = TeacherKeyText.inspect(format: .doc, data: Data("binary".utf8))
        XCTAssertEqual(legacy.status, .failed)
        XCTAssertTrue(legacy.note.contains("docx"))
        let garbage = TeacherKeyText.inspect(format: .docx, data: Data("teacher".utf8))
        XCTAssertEqual(garbage.status, .failed)
    }

    func testVariantCacheAndRadarDoNotInventRows() {
        XCTAssertEqual(WeaknessRadar.emptyMessage, "完成几次核对后才会出现薄弱项")
        XCTAssertTrue(WeaknessRadar.slices(subjects: [], questionTypes: [], errorTags: []).isEmpty)
        let slices = WeaknessRadar.slices(
            subjects: ["数学", "数学"],
            questionTypes: ["计算题"],
            errorTags: ["计算错误", "计算错误", "审题偏差"]
        )
        XCTAssertEqual(slices.first { $0.kind == .subject && $0.label == "数学" }?.count, 2)
        XCTAssertEqual(slices.first { $0.kind == .errorTag && $0.label == "计算错误" }?.count, 2)
        XCTAssertFalse(slices.contains { $0.label == "KnowledgeStat" })

        let id = UUID()
        let key = SimilarCacheFile.key(wrongItemID: id, questionType: "计算题", locale: "zh-Hans")
        XCTAssertTrue(key.contains(id.uuidString))
        XCTAssertTrue(key.contains("计算题"))
        XCTAssertTrue(key.contains("zh-Hans"))
        let file = SimilarCacheFile(
            items: [
                SimilarCacheItem(stem: "计算：2 + 3 = ?", answer: "5", source: "generated"),
                SimilarCacheItem(stem: "重述这道题", answer: nil, source: "generated"),
            ],
            generatedAt: "2026-10-13T00:00:00Z"
        )
        let decoded = SimilarCacheFile.decode(file.encode())
        XCTAssertEqual(decoded?.items.count, 2)
        XCTAssertEqual(decoded?.items[0].answer, "5")
        XCTAssertNil(decoded?.items[1].answer)
        XCTAssertEqual(decoded?.items[0].source, "generated")
        XCTAssertEqual(decoded?.generatedAt, "2026-10-13T00:00:00Z")
        XCTAssertEqual(VariantPractice.check(attempt: "6", answer: "5"), .incorrect)
        XCTAssertEqual(VariantPractice.check(attempt: "5", answer: "5"), .correct)
        XCTAssertEqual(VariantPractice.check(attempt: "任意", answer: nil), .ungraded)
    }

    private func segment(_ text: String, page: Int) -> SheetSegment {
        SheetAligner.questionSegment(
            stem: text,
            crop: CGRect(x: 0, y: 0, width: 1, height: 1),
            confidence: 0.9,
            pageID: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(page)")!
        )
    }

    private func answer(_ text: String, page: Int) -> SheetSegment {
        SheetAligner.answerSegment(
            block: text,
            crop: CGRect(x: 0, y: 0, width: 1, height: 1),
            confidence: 0.9,
            pageID: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(page)")!
        )
    }
}

private extension Data {
    init(hex: String) {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<next], radix: 16) {
                data.append(byte)
            }
            index = next
        }
        self = data
    }
}
