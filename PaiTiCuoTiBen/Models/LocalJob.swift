import Foundation
import SwiftData

@Model
final class LocalJob {
    var id: UUID
    var childID: UUID
    var gradeRaw: String
    var subjectRaw: String
    var answerContextRaw: String
    /// `A` is the same-page flow. `B` aligns question sheets with answer sheets.
    var modeRaw: String
    var statusRaw: String
    var teacherKeyRelativePath: String?
    var teacherKeyFilename: String?
    var teacherKeyFormatRaw: String?
    var teacherKeyStatusRaw: String = ""
    var teacherKeyPlainText: String = ""
    var teacherKeyNote: String = ""
    var createdAt: Date
    var updatedAt: Date
    var child: Child?

    @Relationship(deleteRule: .cascade, inverse: \Page.job)
    var pages: [Page]

    @Relationship(deleteRule: .cascade, inverse: \Question.job)
    var questions: [Question]

    init(
        childID: UUID,
        grade: GradeLevel,
        subject: Subject,
        answerContext: AnswerContext,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.childID = childID
        self.gradeRaw = grade.rawValue
        self.subjectRaw = subject.rawValue
        self.answerContextRaw = answerContext.rawValue
        self.modeRaw = JobMode.a.rawValue
        self.statusRaw = JobStatus.draft.rawValue
        self.teacherKeyRelativePath = nil
        self.teacherKeyFilename = nil
        self.teacherKeyFormatRaw = nil
        self.teacherKeyStatusRaw = ""
        self.teacherKeyPlainText = ""
        self.teacherKeyNote = ""
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.child = nil
        self.pages = []
        self.questions = []
    }

    var grade: GradeLevel {
        get { GradeLevel.resolve(gradeRaw) }
        set { gradeRaw = newValue.rawValue }
    }

    var subject: Subject {
        get { Subject.resolve(subjectRaw) }
        set { subjectRaw = newValue.rawValue }
    }

    var answerContext: AnswerContext {
        get { AnswerContext.resolve(answerContextRaw) }
        set { answerContextRaw = newValue.rawValue }
    }

    var mode: JobMode {
        get { JobMode(rawValue: modeRaw) ?? .a }
        set { modeRaw = newValue.rawValue }
    }

    var status: JobStatus {
        get { JobStatus.resolve(statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    var teacherKeyFormat: TeacherKeyFormat? {
        get { teacherKeyFormatRaw.flatMap(TeacherKeyFormat.init(rawValue:)) }
        set { teacherKeyFormatRaw = newValue?.rawValue }
    }

    var teacherKeyStatus: TeacherKeyStatus {
        get { TeacherKeyStatus.resolve(teacherKeyStatusRaw) }
        set { teacherKeyStatusRaw = newValue.rawValue }
    }

    var alignmentSuccessCount: Int {
        questions.filter { $0.alignmentStatus == .matched }.count
    }

    var alignmentFailureCount: Int {
        questions.filter { $0.alignmentStatus == .failed }.count
    }

    var sortedPages: [Page] {
        pages.sorted { $0.order < $1.order }
    }

    var sortedQuestions: [Question] {
        questions.sorted { $0.order < $1.order }
    }
}
