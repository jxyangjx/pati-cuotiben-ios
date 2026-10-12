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
    var createdAt: Date
    var job: LocalJob?

    init(
        id: UUID = UUID(),
        order: Int,
        imageRelativePath: String,
        pixelWidth: Double,
        pixelHeight: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.order = order
        self.imageRelativePath = imageRelativePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.purged = false
        self.createdAt = createdAt
        self.job = nil
    }
}
