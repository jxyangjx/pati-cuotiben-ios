import Foundation
import SwiftData

@Model
final class Page {
    var id: UUID
    var order: Int
    var imageRelativePath: String
    var pixelWidth: Double
    var pixelHeight: Double
    var purged: Bool
    /// `questionSheet` for mode A. Mode B pages are marked one by one.
    var roleRaw: String = PageRole.questionSheet.rawValue
    var createdAt: Date
    var job: LocalJob?

    init(
        id: UUID = UUID(),
        order: Int,
        imageRelativePath: String,
        pixelWidth: Double,
        pixelHeight: Double,
        role: PageRole = .questionSheet,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.order = order
        self.imageRelativePath = imageRelativePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.purged = false
        self.roleRaw = role.rawValue
        self.createdAt = createdAt
        self.job = nil
    }

    var role: PageRole {
        get { PageRole.resolve(roleRaw) }
        set { roleRaw = newValue.rawValue }
    }
}
