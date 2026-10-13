import Foundation
import SwiftData

@Model
final class Child {
    var id: UUID
    var name: String
    var gradeRaw: String
    var createdAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \LocalJob.child)
    var jobs: [LocalJob]

    @Relationship(deleteRule: .cascade, inverse: \WrongItem.child)
    var wrongItems: [WrongItem]

    init(name: String, grade: GradeLevel, createdAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.gradeRaw = grade.rawValue
        self.createdAt = createdAt
        self.archivedAt = nil
        self.jobs = []
        self.wrongItems = []
    }

    var grade: GradeLevel {
        get { GradeLevel.resolve(gradeRaw) }
        set { gradeRaw = newValue.rawValue }
    }

    var isArchived: Bool { archivedAt != nil }
}
