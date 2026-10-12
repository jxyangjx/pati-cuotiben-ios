import Foundation
import SwiftData

@Model
final class WrongItem {
    var id: UUID
    var childID: UUID
    var sourceQuestionID: UUID
    var sourceJobID: UUID
    var subjectRaw: String
    var gradeRaw: String
    var questionType: String
    var stemText: String
    var cropRelativePath: String?
    var studentAnswerText: String
    var canonicalText: String
    var canonicalStepsJSON: String
    var analysisStatusRaw: String
    var pointsJSON: String
    var avoidanceTipsJSON: String
    var createdAt: Date
    var child: Child?

    init(
        childID: UUID,
        sourceQuestionID: UUID,
        sourceJobID: UUID,
        subject: Subject,
        grade: GradeLevel,
        questionType: String,
        stemText: String,
        studentAnswerText: String,
        canonicalText: String,
        canonicalSteps: [String]
    ) {
        self.id = UUID()
        self.childID = childID
        self.sourceQuestionID = sourceQuestionID
        self.sourceJobID = sourceJobID
        self.subjectRaw = subject.rawValue
        self.gradeRaw = grade.rawValue
        self.questionType = questionType
        self.stemText = stemText
        self.cropRelativePath = nil
        self.studentAnswerText = studentAnswerText
        self.canonicalText = canonicalText
        self.canonicalStepsJSON = JSONList.encode(canonicalSteps)
        self.analysisStatusRaw = AnalysisStatus.pending.rawValue
        self.pointsJSON = JSONList.encode([])
        self.avoidanceTipsJSON = JSONList.encode([])
        self.createdAt = Date()
        self.child = nil
    }

    var subject: Subject {
        get { Subject.resolve(subjectRaw) }
        set { subjectRaw = newValue.rawValue }
    }

    var grade: GradeLevel {
        get { GradeLevel.resolve(gradeRaw) }
        set { gradeRaw = newValue.rawValue }
    }

    var canonicalSteps: [String] {
        get { JSONList.decode(canonicalStepsJSON) }
        set { canonicalStepsJSON = JSONList.encode(newValue) }
    }

    var analysisStatus: AnalysisStatus {
        get { AnalysisStatus.resolve(analysisStatusRaw) }
        set { analysisStatusRaw = newValue.rawValue }
    }

    var points: [String] {
        get { JSONList.decode(pointsJSON) }
        set { pointsJSON = JSONList.encode(newValue) }
    }

    var avoidanceTips: [String] {
        get { JSONList.decode(avoidanceTipsJSON) }
        set { avoidanceTipsJSON = JSONList.encode(newValue) }
    }
}
