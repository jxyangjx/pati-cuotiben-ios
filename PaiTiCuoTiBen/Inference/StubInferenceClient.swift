import Foundation

/// Offline stand-in for solve / grade / error-analysis / summary-groups.
struct StubInferenceClient: InferenceClient {
    func solve(_ request: SolveRequest) async throws -> SolveResponse {
        let stem = request.stemText.replacingOccurrences(of: " ", with: "")
        let refs = request.teacherKeyFilename.map { ["teacher-key:\($0)"] } ?? []
        if stem.contains("1+1") {
            return SolveResponse(
                text: "2",
                steps: ["1 加 1 得 2。"],
                explanation: "这是一步加法。",
                questionType: "计算题",
                confidence: 0.93,
                sourceRefs: refs
            )
        }
        return SolveResponse(
            text: "（模拟标答）请核对本题最终答案",
            steps: ["低置信模拟步骤：确认前不会锁定对错，也不会进入错题本。"],
            explanation: "开放题在离线桩里保持待确认。",
            questionType: "解答题",
            confidence: 0.58,
            sourceRefs: refs
        )
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        let student = GradingPolicy.normalizeAnswer(request.studentAnswer)
        let canonical = GradingPolicy.normalizeAnswer(request.canonicalText)
        if student.isEmpty || canonical.isEmpty {
            return GradeResponse(result: .pending, confidence: 0.2, suggestedAuthority: .none)
        }
        if student == canonical {
            return GradeResponse(result: .correct, confidence: 0.96, suggestedAuthority: .autoObjective)
        }
        if request.canonicalConfidence >= GradingPolicy.defaultLockThreshold,
           GradingPolicy.looksObjective(canonical: request.canonicalText, questionType: request.questionType) {
            return GradeResponse(result: .wrong, confidence: 0.91, suggestedAuthority: .autoObjective)
        }
        return GradeResponse(result: .wrong, confidence: 0.6, suggestedAuthority: .none)
    }

    func errorAnalysis(_ request: ErrorAnalysisRequest) async throws -> ErrorAnalysisResponse {
        let student = clip(request.studentAnswer)
        let canonical = clip(request.canonicalText)
        return ErrorAnalysisResponse(
            points: [
                "作答「\(student)」和系统标答「\(canonical)」不一致。",
                "核对这道\(request.questionType)的关键步骤，不要只看最后几个字。",
            ],
            avoidanceTips: [
                "先自己把步骤写完整，再对照标答逐行看。",
                "下次做\(request.subject)的\(request.questionType)，先圈出已知条件。",
            ],
            tags: request.questionType == "计算题" ? ["计算错误"] : ["审题偏差"]
        )
    }

    func summaryGroups(_ request: SummaryGroupsRequest) async throws -> [SummaryGroup] {
        let grouped = Dictionary(grouping: request.questions, by: \.questionType)
        return grouped.keys.sorted().map { type in
            let items = grouped[type] ?? []
            let correct = items.filter { $0.result == .correct }.count
            let wrong = items.filter { $0.result == .wrong }.count
            let pending = items.filter { $0.result == .pending }.count
            var bullets = ["共 \(items.count) 题：正确 \(correct)，错误 \(wrong)，待确认 \(pending)。"]
            if pending > 0 {
                bullets.append("待确认的题会留在这次总结里。确认判错之后才会进入错题本。")
            }
            if wrong > 0 {
                bullets.append("错误题可以先看自己的作答和系统标答，错因会补在错题本里。")
            }
            if wrong == 0 && pending == 0 {
                bullets.append("这一类目前没有待处理的错题。")
            }
            return SummaryGroup(
                questionType: type,
                correctCount: correct,
                wrongCount: wrong,
                pendingCount: pending,
                bullets: bullets
            )
        }
    }

    func similar(_ request: SimilarQuestionRequest) async throws -> SimilarQuestionResponse {
        let stem = request.stemText.replacingOccurrences(of: " ", with: "")
        if stem.contains("1+1") || request.canonicalText == "2" {
            return SimilarQuestionResponse(items: [
                SimilarQuestionItem(stem: "计算：2 + 3 = ?", answer: "5", source: "generated"),
                SimilarQuestionItem(stem: "计算：4 + 1 = ?", answer: "5", source: "generated"),
                SimilarQuestionItem(stem: "计算：6 - 4 = ?", answer: "2", source: "generated"),
            ])
        }
        let clipped = clip(request.stemText)
        return SimilarQuestionResponse(items: [
            SimilarQuestionItem(
                stem: "变式：把「\(clipped)」里的一个条件换掉，再答一次。",
                answer: request.canonicalText,
                source: "generated"
            ),
            SimilarQuestionItem(
                stem: "变式：用自己的话重述这道\(request.questionType)，并写出最终答案。",
                answer: nil,
                source: "generated"
            ),
        ])
    }

    private func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40)) + "…"
    }
}
