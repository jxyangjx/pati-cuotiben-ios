import CoreGraphics
import Foundation
import SwiftData

struct PageRecognitionOutcome: Equatable {
    var questionCount: Int
    var emptyPageNumbers: [Int]
}

@MainActor
enum JobPipeline {
    static func activeChildren(context: ModelContext) -> [Child] {
        fetch(Child.self, context: context)
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func createChild(name: String, grade: GradeLevel, context: ModelContext) throws -> Child {
        try PrivacyConsent.require()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.invalidName }
        guard ChildPolicy.canActivate(activeCount: activeChildren(context: context).count) else {
            throw AppError.childLimit
        }
        let child = Child(name: String(trimmed.prefix(20)), grade: grade)
        context.insert(child)
        try context.save()
        return child
    }

    static func updateChild(_ child: Child, name: String, grade: GradeLevel, context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.invalidName }
        child.name = String(trimmed.prefix(20))
        child.grade = grade
        try context.save()
    }

    static func archive(_ child: Child, context: ModelContext) throws {
        child.archivedAt = Date()
        try context.save()
    }

    static func restore(_ child: Child, context: ModelContext) throws {
        guard child.isArchived else { return }
        guard ChildPolicy.canActivate(activeCount: activeChildren(context: context).count) else {
            throw AppError.childLimit
        }
        child.archivedAt = nil
        try context.save()
    }

    static func deleteChild(_ child: Child, context: ModelContext) throws {
        let childID = child.id
        context.delete(child)
        try context.save()
        SandboxStore.removeTree(relativePath: SandboxPath.childDirectory(childID: childID))
    }

    static func createDraft(
        child: Child,
        grade: GradeLevel,
        subject: Subject,
        answerContext: AnswerContext,
        context: ModelContext
    ) throws -> LocalJob {
        let job = LocalJob(
            childID: child.id,
            grade: grade,
            subject: subject,
            answerContext: answerContext
        )
        context.insert(job)
        job.child = child
        try context.save()
        return job
    }

    static func addPage(
        job: LocalJob,
        imageData: Data,
        context: ModelContext,
        role: PageRole = .questionSheet
    ) throws {
        let pageID = UUID()
        let path = SandboxPath.page(childID: job.childID, jobID: job.id, pageID: pageID)
        let saved = try SandboxStore.saveJPEG(imageData, relativePath: path)
        let page = Page(
            id: pageID,
            order: job.pages.count,
            imageRelativePath: saved.path,
            pixelWidth: saved.width,
            pixelHeight: saved.height,
            role: role
        )
        context.insert(page)
        page.job = job
        job.updatedAt = Date()
        try context.save()
    }

    static func setMode(job: LocalJob, mode: JobMode, context: ModelContext) throws {
        job.mode = mode
        if mode == .a {
            for page in job.pages {
                page.role = .questionSheet
            }
        }
        job.updatedAt = Date()
        try context.save()
    }

    static func setPageRole(page: Page, job: LocalJob, role: PageRole, context: ModelContext) throws {
        page.role = role
        job.updatedAt = Date()
        try context.save()
    }

    static func movePage(job: LocalJob, pageID: UUID, before targetID: UUID, context: ModelContext) throws {
        var pages = job.sortedPages
        guard let from = pages.firstIndex(where: { $0.id == pageID }) else { return }
        guard pages.contains(where: { $0.id == targetID }), pageID != targetID else { return }
        let moving = pages.remove(at: from)
        let insertAt = pages.firstIndex(where: { $0.id == targetID }) ?? pages.endIndex
        pages.insert(moving, at: insertAt)
        for (order, page) in pages.enumerated() {
            page.order = order
        }
        job.updatedAt = Date()
        try context.save()
    }

    static func replacePage(_ page: Page, job: LocalJob, imageData: Data, context: ModelContext) throws {
        if page.imageRelativePath.isEmpty {
            page.imageRelativePath = SandboxPath.page(
                childID: job.childID,
                jobID: job.id,
                pageID: page.id
            )
        }
        let saved = try SandboxStore.saveJPEG(imageData, relativePath: page.imageRelativePath)
        page.pixelWidth = saved.width
        page.pixelHeight = saved.height
        page.purged = false
        job.updatedAt = Date()
        try context.save()
    }

    static func shiftPage(job: LocalJob, pageID: UUID, direction: Int, context: ModelContext) throws {
        var pages = job.sortedPages
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let target = index + direction
        guard pages.indices.contains(target) else { return }
        pages.swapAt(index, target)
        for (order, page) in pages.enumerated() {
            page.order = order
        }
        job.updatedAt = Date()
        try context.save()
    }

    static func deletePage(job: LocalJob, pageID: UUID, context: ModelContext) throws {
        guard let page = job.pages.first(where: { $0.id == pageID }) else { return }
        let related = job.questions.filter { $0.pageID == page.id }
        for question in related {
            try deleteWrongItems(sourceQuestionID: question.id, context: context)
            context.delete(question)
        }
        SandboxStore.remove(relativePath: page.imageRelativePath)
        context.delete(page)
        let remaining = job.sortedPages.filter { $0.id != pageID }
        for (order, page) in remaining.enumerated() {
            page.order = order
        }
        job.updatedAt = Date()
        try context.save()
    }

    static func importTeacherKey(job: LocalJob, filename: String, data: Data, context: ModelContext) throws {
        guard data.count <= SandboxStore.teacherKeyByteLimit else { throw AppError.teacherKeyTooLarge }
        let format = TeacherKeyFormat.detect(filename: filename)
        guard format != .unknown else { throw AppError.teacherKeyFormat }
        let path = SandboxPath.teacherKey(childID: job.childID, jobID: job.id, filename: filename)
        if let previous = job.teacherKeyRelativePath, previous != path {
            SandboxStore.remove(relativePath: previous)
        }
        try SandboxStore.write(data, relativePath: path)
        let inspection = TeacherKeyText.inspect(format: format, data: data)
        job.teacherKeyRelativePath = path
        job.teacherKeyFilename = filename
        job.teacherKeyFormat = format
        job.teacherKeyStatus = inspection.status
        job.teacherKeyPlainText = inspection.text
        job.teacherKeyNote = inspection.note
        job.updatedAt = Date()
        try context.save()
    }

    static func removeTeacherKey(job: LocalJob, context: ModelContext) throws {
        SandboxStore.remove(relativePath: job.teacherKeyRelativePath)
        job.teacherKeyRelativePath = nil
        job.teacherKeyFilename = nil
        job.teacherKeyFormat = nil
        job.teacherKeyStatus = .none
        job.teacherKeyPlainText = ""
        job.teacherKeyNote = ""
        job.updatedAt = Date()
        try context.save()
    }

    @discardableResult
    static func recognizePages(
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double,
        recognizer: any PageTextRecognizing = VisionPageTextRecognizer()
    ) async throws -> PageRecognitionOutcome {
        try PrivacyConsent.require()
        let pages = job.sortedPages
        guard !pages.isEmpty else { throw AppError.noPages }
        if job.mode == .b {
            let hasQuestions = pages.contains { $0.role == .questionSheet }
            let hasAnswers = pages.contains { $0.role == .answerSheet }
            guard hasQuestions, hasAnswers else { throw AppError.modeBNeedsBoth }
        }

        let teacher = try await loadTeacherContext(job: job, context: context, recognizer: recognizer)
        let gathered = job.mode == .b
            ? try await gatherModeB(pages: pages, recognizer: recognizer)
            : try await gatherModeA(pages: pages, recognizer: recognizer)
        guard !gathered.cards.isEmpty else { throw AppError.noPrintedText }

        var prepared: [PreparedQuestion] = []
        for card in gathered.cards {
            var solved = try await inference.solve(
                SolveRequest(
                    stemText: card.draft.stem,
                    studentAnswer: card.draft.studentAnswer,
                    subject: job.subjectRaw,
                    grade: job.gradeRaw,
                    teacherKeyFilename: job.teacherKeyFilename
                )
            )
        let alignedText = TeacherAnswerAligner.alignedText(
            systemText: solved.text,
            questionNumber: card.number,
            answers: teacher.answers,
            plainText: teacher.plainText,
            soleQuestion: gathered.cards.count == 1
        )
        solved = SolveResponse(
            text: alignedText,
            steps: solved.steps,
            explanation: solved.explanation,
            questionType: solved.questionType,
            confidence: solved.confidence,
            sourceRefs: solved.sourceRefs
        )
            prepared.append(
                PreparedQuestion(
                    page: card.page,
                    draft: card.draft,
                    solved: solved,
                    questionNumber: card.number,
                    alignmentStatus: card.alignment,
                    alignmentCode: card.code,
                    origin: card.origin,
                    markHint: card.hint
                )
            )
        }
        let emptyPageNumbers = gathered.empty

        for question in Array(job.questions) {
            try deleteWrongItems(sourceQuestionID: question.id, context: context)
            SandboxStore.remove(relativePath: question.cropRelativePath)
            context.delete(question)
        }

        for (order, item) in prepared.enumerated() {
            try await install(
                item: item,
                order: order,
                job: job,
                context: context,
                inference: inference,
                threshold: threshold
            )
        }

        job.status = .reviewing
        job.updatedAt = Date()
        try context.save()
        return PageRecognitionOutcome(questionCount: prepared.count, emptyPageNumbers: emptyPageNumbers)
    }

    static func confirmCanonical(
        question: Question,
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double
    ) async throws {
        question.verdict?.holdPending = false
        try await regrade(
            question: question,
            job: job,
            context: context,
            inference: inference,
            threshold: threshold,
            adoption: .user,
            verdictOverride: nil,
            userHoldPending: false
        )
    }

    static func judge(
        question: Question,
        job: LocalJob,
        result: VerdictResult,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double
    ) async throws {
        if result == .pending {
            question.verdict?.holdPending = true
            try await regrade(
                question: question,
                job: job,
                context: context,
                inference: inference,
                threshold: threshold,
                adoption: question.canonicalAnswer?.adoption ?? .none,
                verdictOverride: nil,
                userHoldPending: true
            )
            return
        }
        question.verdict?.holdPending = false
        try await regrade(
            question: question,
            job: job,
            context: context,
            inference: inference,
            threshold: threshold,
            adoption: .user,
            verdictOverride: result,
            userHoldPending: false
        )
    }

    /// Rebuilds the canonical answer from the current stem and student snapshot, then grades again.
    static func reprocessEditedText(
        question: Question,
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double
    ) async throws {
        try PrivacyConsent.require()
        guard let canonical = question.canonicalAnswer else { throw AppError.missingCanonical }
        let solved = try await inference.solve(
            SolveRequest(
                stemText: question.stemText,
                studentAnswer: question.answer?.snapshotText ?? "",
                subject: job.subjectRaw,
                grade: job.gradeRaw,
                teacherKeyFilename: job.teacherKeyFilename
            )
        )
        let teacherAnswers = job.teacherKeyStatus == .parsed
            ? TeacherAnswerAligner.map(from: job.teacherKeyPlainText)
            : [:]
        let plain = job.teacherKeyStatus == .parsed ? job.teacherKeyPlainText : ""
        canonical.text = TeacherAnswerAligner.alignedText(
            systemText: solved.text,
            questionNumber: question.questionNumber,
            answers: teacherAnswers,
            plainText: plain,
            soleQuestion: job.questions.count == 1
        )
        canonical.steps = solved.steps.isEmpty ? ["（步骤待补充）"] : solved.steps
        canonical.explanation = solved.explanation
        canonical.confidence = solved.confidence
        canonical.sourceRefs = solved.sourceRefs
        question.questionType = solved.questionType
        question.verdict?.holdPending = false
        try await regrade(
            question: question,
            job: job,
            context: context,
            inference: inference,
            threshold: threshold,
            adoption: .none,
            verdictOverride: nil,
            userHoldPending: false
        )
    }

    static func invalidateCanonical(question: Question, job: LocalJob, context: ModelContext) throws {
        guard let canonical = question.canonicalAnswer, let verdict = question.verdict else { return }
        guard canonical.confirmation == .confirmed || verdict.locked else { return }
        canonical.confirmation = .pending
        canonical.adoptedAuthority = .none
        canonical.stepsNeedReview = true
        verdict.result = .pending
        verdict.authority = .none
        verdict.locked = false
        verdict.holdPending = false
        verdict.leaning = nil
        try deleteWrongItems(sourceQuestionID: question.id, context: context)
        job.status = .reviewing
        job.updatedAt = Date()
        try context.save()
    }

    static func retryAnalysis(
        item: WrongItem,
        context: ModelContext,
        inference: any InferenceClient
    ) async {
        guard let question = fetch(Question.self, context: context).first(where: { $0.id == item.sourceQuestionID }) else {
            await analyzeStored(item: item, context: context, inference: inference)
            return
        }
        await analyze(question: question, context: context, inference: inference)
    }

    @discardableResult
    static func clearDrafts(context: ModelContext) throws -> Int {
        let drafts = fetch(LocalJob.self, context: context).filter { $0.status == .draft }
        for job in drafts {
            deleteJob(job, context: context)
        }
        if !drafts.isEmpty {
            try context.save()
        }
        return drafts.count
    }

    @discardableResult
    static func purgeOriginals(olderThan days: Int, context: ModelContext) throws -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var count = 0
        for page in fetch(Page.self, context: context) where !page.purged && !page.imageRelativePath.isEmpty {
            if page.createdAt < cutoff {
                SandboxStore.remove(relativePath: page.imageRelativePath)
                page.imageRelativePath = ""
                page.purged = true
                count += 1
            }
        }
        try context.save()
        return count
    }

    static func realign(
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double
    ) async throws {
        let questions = job.sortedQuestions
        let results = SheetAligner.realign(
            questions.map { question in
                RealignCard(
                    number: question.questionNumber,
                    stem: question.stemText,
                    answer: question.answer?.snapshotText ?? "",
                    origin: question.origin ?? .questionSheet
                )
            }
        )
        for (question, result) in zip(questions, results) {
            question.questionNumber = QuestionNumbers.normalize(question.questionNumber)
            question.alignmentStatus = result.status
            question.alignmentCode = result.code
            let preserveUserLock = result.status == .matched
                && question.verdict?.locked == true
                && question.verdict?.authority == .userConfirm
            try await regrade(
                question: question,
                job: job,
                context: context,
                inference: inference,
                threshold: threshold,
                adoption: preserveUserLock ? .user : (question.canonicalAnswer?.adoption ?? .none),
                verdictOverride: preserveUserLock ? question.verdict?.result : nil,
                userHoldPending: false
            )
        }
    }

    static func cachedSimilar(item: WrongItem, locale: String) -> SimilarCacheFile? {
        let key = SimilarCacheFile.key(wrongItemID: item.id, questionType: item.questionType, locale: locale)
        guard item.similarCacheKey == key else { return nil }
        return SimilarCacheFile.decode(item.similarCacheJSON)
    }

    @discardableResult
    static func generateSimilar(
        item: WrongItem,
        context: ModelContext,
        inference: any InferenceClient,
        locale: String,
        replacingCache: Bool = false
    ) async throws -> SimilarCacheFile {
        if !replacingCache, let cached = cachedSimilar(item: item, locale: locale) {
            return cached
        }
        let response = try await inference.similar(
            SimilarQuestionRequest(
                stemText: item.stemText,
                canonicalText: item.canonicalText,
                questionType: item.questionType,
                subject: item.subjectRaw,
                locale: locale
            )
        )
        try Task.checkCancellation()
        let normalized = Array(SimilarCacheFile.normalized(response.items).prefix(3))
        guard normalized.count >= 2, normalized.count <= 3 else { throw AppError.inferenceFailed }
        let file = SimilarCacheFile(items: normalized, generatedAt: isoTimestamp(Date()))
        item.similarCacheKey = SimilarCacheFile.key(
            wrongItemID: item.id,
            questionType: item.questionType,
            locale: locale
        )
        item.similarCacheJSON = file.encode()
        try context.save()
        return file
    }

    static func markCompleted(job: LocalJob, context: ModelContext) throws {
        guard job.status == .reviewing else { return }
        job.status = .completed
        job.updatedAt = Date()
        try context.save()
    }

    static func deleteJob(_ job: LocalJob, context: ModelContext) {
        let childID = job.childID
        let jobID = job.id
        context.delete(job)
        SandboxStore.removeTree(relativePath: SandboxPath.jobDirectory(childID: childID, jobID: jobID))
    }

    private static func regrade(
        question: Question,
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double,
        adoption: CanonicalAdoption,
        verdictOverride: VerdictResult?,
        userHoldPending: Bool
    ) async throws {
        guard let canonical = question.canonicalAnswer else { throw AppError.missingCanonical }
        let steps = canonical.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if adoption == .user || verdictOverride != nil {
            guard !canonical.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !steps.isEmpty else {
                throw AppError.missingCanonical
            }
            canonical.steps = steps
        }
        let graded = try await inference.grade(
            GradeRequest(
                studentAnswer: question.answer?.snapshotText ?? "",
                canonicalText: canonical.text,
                questionType: question.questionType,
                canonicalConfidence: canonical.confidence
            )
        )
        let decision = GradingPolicy.decide(
            student: question.answer?.snapshotText ?? "",
            canonical: canonical.text,
            steps: canonical.steps,
            questionType: question.questionType,
            canonicalConfidence: canonical.confidence,
            grade: GradeSignal(
                result: graded.result,
                confidence: graded.confidence,
                suggestedAuthority: graded.suggestedAuthority
            ),
            adoption: adoption,
            verdictOverride: verdictOverride,
            userHoldPending: userHoldPending,
            suppressAutoLock: question.alignmentStatus == .failed,
            threshold: threshold
        )
        try await apply(
            decision: decision,
            question: question,
            job: job,
            context: context,
            inference: inference,
            runAnalysis: true
        )
        job.updatedAt = Date()
        if job.status == .completed {
            job.status = .reviewing
        }
        try context.save()
    }

    private static func apply(
        decision: GradingDecision,
        question: Question,
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        runAnalysis: Bool
    ) async throws {
        guard let canonical = question.canonicalAnswer, let verdict = question.verdict else { return }
        canonical.confirmation = decision.canonicalConfirmation
        canonical.adoptedAuthority = decision.canonicalAuthority
        canonical.stepsNeedReview = decision.stepsNeedReview
        verdict.result = decision.verdict
        verdict.authority = decision.verdictAuthority
        verdict.confidence = decision.verdictConfidence
        verdict.locked = decision.locked
        verdict.leaning = decision.leaning
        verdict.holdPending = decision.locked ? false : verdict.holdPending

        if decision.canEnterWrongBook {
            let item = try upsertWrongItem(question: question, job: job, context: context)
            if runAnalysis {
                await runAnalysis(
                    item: item,
                    stem: question.stemText,
                    student: item.studentAnswerText,
                    canonical: item.canonicalText,
                    steps: item.canonicalSteps,
                    questionType: item.questionType,
                    subject: job.subjectRaw,
                    context: context,
                    inference: inference
                )
            }
        } else {
            try deleteWrongItems(sourceQuestionID: question.id, context: context)
        }
    }

    @discardableResult
    private static func upsertWrongItem(question: Question, job: LocalJob, context: ModelContext) throws -> WrongItem {
        guard let canonical = question.canonicalAnswer else { throw AppError.missingCanonical }
        let steps = canonical.steps.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !steps.isEmpty else { throw AppError.missingCanonical }
        let student = question.answer?.snapshotText ?? ""
        let existing = fetch(WrongItem.self, context: context).first { $0.sourceQuestionID == question.id }
        let item = existing ?? WrongItem(
            childID: job.childID,
            sourceQuestionID: question.id,
            sourceJobID: job.id,
            subject: job.subject,
            grade: job.grade,
            questionType: question.questionType,
            stemText: question.stemText,
            studentAnswerText: student,
            canonicalText: canonical.text,
            canonicalSteps: steps
        )
        if existing == nil {
            context.insert(item)
            let child = job.child ?? fetch(Child.self, context: context).first { $0.id == job.childID }
            item.child = child
        }
        let changed = item.studentAnswerText != student
            || item.canonicalText != canonical.text
            || item.canonicalSteps != steps
            || item.stemText != question.stemText
        if item.questionType != question.questionType {
            item.similarCacheJSON = ""
            item.similarCacheKey = ""
        }
        item.subject = job.subject
        item.grade = job.grade
        item.questionType = question.questionType
        item.stemText = question.stemText
        item.studentAnswerText = student
        item.canonicalText = canonical.text
        item.canonicalSteps = steps
        item.sourceJobID = job.id
        if changed {
            item.analysisStatus = .pending
            item.points = []
            item.avoidanceTips = []
            item.errorTags = []
        }
        if let crop = question.cropRelativePath, SandboxStore.fileExists(relativePath: crop) {
            let destination = SandboxPath.wrongCrop(childID: job.childID, wrongItemID: item.id)
            if (try? SandboxStore.copyFile(from: crop, to: destination)) != nil {
                item.cropRelativePath = destination
            }
        }
        return item
    }

    private static func analyze(
        question: Question,
        context: ModelContext,
        inference: any InferenceClient
    ) async {
        guard let item = fetch(WrongItem.self, context: context).first(where: { $0.sourceQuestionID == question.id }) else {
            return
        }
        let subject = question.job?.subjectRaw ?? item.subjectRaw
        await runAnalysis(
            item: item,
            stem: question.stemText,
            student: item.studentAnswerText,
            canonical: item.canonicalText,
            steps: item.canonicalSteps,
            questionType: item.questionType,
            subject: subject,
            context: context,
            inference: inference
        )
    }

    private static func analyzeStored(
        item: WrongItem,
        context: ModelContext,
        inference: any InferenceClient
    ) async {
        await runAnalysis(
            item: item,
            stem: item.stemText,
            student: item.studentAnswerText,
            canonical: item.canonicalText,
            steps: item.canonicalSteps,
            questionType: item.questionType,
            subject: item.subjectRaw,
            context: context,
            inference: inference
        )
    }

    private static func runAnalysis(
        item: WrongItem,
        stem: String,
        student: String,
        canonical: String,
        steps: [String],
        questionType: String,
        subject: String,
        context: ModelContext,
        inference: any InferenceClient
    ) async {
        item.analysisStatus = .pending
        do {
            let response = try await inference.errorAnalysis(
                ErrorAnalysisRequest(
                    stemText: stem,
                    studentAnswer: student,
                    canonicalText: canonical,
                    steps: steps,
                    questionType: questionType,
                    subject: subject
                )
            )
            let points = AnalysisText.points(response.points)
            let tips = AnalysisText.tips(response.avoidanceTips)
            guard !points.isEmpty, !tips.isEmpty else {
                item.errorTags = []
                item.analysisStatus = .failed
                try? context.save()
                return
            }
            item.points = points
            item.avoidanceTips = tips
            item.errorTags = AnalysisText.tags(response.tags)
            item.analysisStatus = .ready
        } catch {
            item.errorTags = []
            item.analysisStatus = .failed
        }
        try? context.save()
    }

    private struct TeacherContext {
        var answers: [String: String]
        var plainText: String
    }

    private struct GatheredCard {
        var page: Page
        var draft: QuestionDraft
        var number: String
        var alignment: AlignmentStatus?
        var code: AlignmentCode?
        var origin: QuestionOrigin
        var hint: String?
    }

    private struct PreparedQuestion {
        var page: Page
        var draft: QuestionDraft
        var solved: SolveResponse
        var questionNumber: String
        var alignmentStatus: AlignmentStatus?
        var alignmentCode: AlignmentCode?
        var origin: QuestionOrigin
        var markHint: String?
    }

    private static func loadTeacherContext(
        job: LocalJob,
        context: ModelContext,
        recognizer: any PageTextRecognizing
    ) async throws -> TeacherContext {
        if job.teacherKeyFormat == .image, job.teacherKeyStatus != .parsed,
           let path = job.teacherKeyRelativePath,
           let data = SandboxStore.read(relativePath: path), !data.isEmpty {
            let lines = (try? await recognizer.recognize(imageData: data)) ?? []
            let inspection = TeacherKeyText.plainText(fromOCR: lines.map(\.text))
            job.teacherKeyStatus = inspection.status
            job.teacherKeyPlainText = inspection.text
            job.teacherKeyNote = inspection.note
            try context.save()
        }
        guard job.teacherKeyStatus == .parsed else {
            return TeacherContext(answers: [:], plainText: "")
        }
        return TeacherContext(
            answers: TeacherAnswerAligner.map(from: job.teacherKeyPlainText),
            plainText: job.teacherKeyPlainText
        )
    }

    private static func gatherModeA(
        pages: [Page],
        recognizer: any PageTextRecognizing
    ) async throws -> (cards: [GatheredCard], empty: [Int]) {
        var cards: [GatheredCard] = []
        var empty: [Int] = []
        for page in pages {
            let pageDrafts = try await drafts(on: page, recognizer: recognizer, takingLastLineAsAnswer: true)
            if pageDrafts.isEmpty {
                empty.append(page.order + 1)
                continue
            }
            for draft in pageDrafts {
                cards.append(
                    GatheredCard(
                        page: page,
                        draft: draft,
                        number: QuestionNumbers.number(in: draft.stem) ?? "",
                        alignment: nil,
                        code: nil,
                        origin: .questionSheet,
                        hint: nil
                    )
                )
            }
        }
        return (cards, empty)
    }

    private static func gatherModeB(
        pages: [Page],
        recognizer: any PageTextRecognizing
    ) async throws -> (cards: [GatheredCard], empty: [Int]) {
        var questions: [SheetSegment] = []
        var answers: [SheetSegment] = []
        var empty: [Int] = []
        var pagesByID: [UUID: Page] = [:]
        for page in pages where page.role == .questionSheet {
            pagesByID[page.id] = page
            let blocks = try await drafts(on: page, recognizer: recognizer, takingLastLineAsAnswer: false)
            if blocks.isEmpty {
                empty.append(page.order + 1)
                continue
            }
            for block in blocks {
                questions.append(
                    SheetAligner.questionSegment(
                        stem: block.stem,
                        crop: block.crop,
                        confidence: block.confidence,
                        pageID: page.id
                    )
                )
            }
        }
        for page in pages where page.role == .answerSheet {
            pagesByID[page.id] = page
            let blocks = try await drafts(on: page, recognizer: recognizer, takingLastLineAsAnswer: false)
            if blocks.isEmpty {
                empty.append(page.order + 1)
                continue
            }
            for block in blocks {
                answers.append(
                    SheetAligner.answerSegment(
                        block: block.stem,
                        crop: block.crop,
                        confidence: block.confidence,
                        pageID: page.id
                    )
                )
            }
        }
        let cards = SheetAligner.align(questions: questions, answers: answers).compactMap { aligned -> GatheredCard? in
            guard let page = pagesByID[aligned.pageID] else { return nil }
            return GatheredCard(
                page: page,
                draft: QuestionDraft(
                    stem: aligned.stem,
                    studentAnswer: aligned.studentAnswer,
                    crop: aligned.crop,
                    confidence: aligned.confidence
                ),
                number: aligned.questionNumber,
                alignment: aligned.status,
                code: aligned.code,
                origin: aligned.origin,
                hint: aligned.markHint
            )
        }
        return (cards, empty)
    }

    private static func drafts(
        on page: Page,
        recognizer: any PageTextRecognizing,
        takingLastLineAsAnswer: Bool = true
    ) async throws -> [QuestionDraft] {
        guard !page.purged, let data = SandboxStore.read(relativePath: page.imageRelativePath), !data.isEmpty else {
            throw AppError.recognitionFailed
        }
        do {
            let lines = try await recognizer.recognize(imageData: data)
            return PrintedQuestionSegmenter.segment(lines, takingLastLineAsAnswer: takingLastLineAsAnswer)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.recognitionFailed
        }
    }

    private static func install(
        item: PreparedQuestion,
        order: Int,
        job: LocalJob,
        context: ModelContext,
        inference: any InferenceClient,
        threshold: Double
    ) async throws {
        let draft = item.draft
        let solved = item.solved
        let question = Question(
            order: order,
            pageID: item.page.id,
            stemText: draft.stem,
            questionType: solved.questionType,
            stemRawOCR: draft.stem,
            ocrConfidence: draft.confidence,
            crop: draft.crop
        )
        question.questionNumber = item.questionNumber
        question.alignmentStatus = item.alignmentStatus
        question.alignmentCode = item.alignmentCode
        question.origin = item.origin
        context.insert(question)
        question.job = job
        attachCrop(question: question, page: item.page, job: job, crop: draft.crop)

        let steps = solved.steps.isEmpty ? ["（步骤待补充）"] : solved.steps
        let canonical = CanonicalAnswer(
            text: solved.text,
            steps: steps,
            explanation: solved.explanation,
            confidence: solved.confidence,
            sourceRefs: solved.sourceRefs
        )
        context.insert(canonical)
        question.canonicalAnswer = canonical

        let markHints = (job.answerContext == .selfMark || item.markHint != nil) ? MarkHints.unreliable : nil
        let answer = Answer(rawOCR: draft.studentAnswer, markHints: markHints)
        context.insert(answer)
        question.answer = answer

        let verdict = Verdict()
        context.insert(verdict)
        question.verdict = verdict

        let graded = try await inference.grade(
            GradeRequest(
                studentAnswer: answer.snapshotText,
                canonicalText: canonical.text,
                questionType: question.questionType,
                canonicalConfidence: canonical.confidence
            )
        )
        let decision = GradingPolicy.decide(
            student: answer.snapshotText,
            canonical: canonical.text,
            steps: canonical.steps,
            questionType: question.questionType,
            canonicalConfidence: canonical.confidence,
            grade: GradeSignal(
                result: graded.result,
                confidence: graded.confidence,
                suggestedAuthority: graded.suggestedAuthority
            ),
            adoption: .none,
            verdictOverride: nil,
            userHoldPending: false,
            suppressAutoLock: item.alignmentStatus == .failed,
            threshold: threshold
        )
        try await apply(
            decision: decision,
            question: question,
            job: job,
            context: context,
            inference: inference,
            runAnalysis: true
        )
    }

    private static func attachCrop(question: Question, page: Page, job: LocalJob, crop: CGRect) {
        guard !page.purged, SandboxStore.fileExists(relativePath: page.imageRelativePath) else { return }
        let cropPath = SandboxPath.crop(childID: job.childID, jobID: job.id, questionID: question.id)
        do {
            try SandboxStore.cropJPEG(
                from: page.imageRelativePath,
                normalizedTopLeft: crop,
                destination: cropPath
            )
            question.cropRelativePath = cropPath
        } catch {
            if (try? SandboxStore.copyFile(from: page.imageRelativePath, to: cropPath)) != nil {
                question.cropRelativePath = cropPath
            }
        }
    }

    private static func deleteWrongItems(sourceQuestionID: UUID, context: ModelContext) throws {
        let items = fetch(WrongItem.self, context: context).filter { $0.sourceQuestionID == sourceQuestionID }
        for item in items {
            SandboxStore.remove(relativePath: item.cropRelativePath)
            context.delete(item)
        }
    }

    private static func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}
