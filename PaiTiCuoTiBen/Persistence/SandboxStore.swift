import Foundation
import UIKit

enum SandboxError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "这张图片无法读取，请换一张。"
        }
    }
}

enum SandboxPath {
    static func page(childID: UUID, jobID: UUID, pageID: UUID) -> String {
        "children/\(childID.uuidString)/jobs/\(jobID.uuidString)/pages/\(pageID.uuidString).jpg"
    }

    static func crop(childID: UUID, jobID: UUID, questionID: UUID) -> String {
        "children/\(childID.uuidString)/jobs/\(jobID.uuidString)/crops/\(questionID.uuidString).jpg"
    }

    static func wrongCrop(childID: UUID, wrongItemID: UUID) -> String {
        "children/\(childID.uuidString)/wrong/\(wrongItemID.uuidString).jpg"
    }

    static func teacherKey(childID: UUID, jobID: UUID, filename: String) -> String {
        let safe = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "children/\(childID.uuidString)/jobs/\(jobID.uuidString)/teacher-key/\(safe)"
    }

    static func jobDirectory(childID: UUID, jobID: UUID) -> String {
        "children/\(childID.uuidString)/jobs/\(jobID.uuidString)"
    }

    static func childDirectory(childID: UUID) -> String {
        "children/\(childID.uuidString)"
    }
}

enum SandboxStore {
    static let teacherKeyByteLimit = 30 * 1024 * 1024

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(relativePath: String) -> URL {
        documentsURL.appendingPathComponent(relativePath)
    }

    static func write(_ data: Data, relativePath: String) throws {
        let destination = url(relativePath: relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    static func read(relativePath: String) -> Data? {
        try? Data(contentsOf: url(relativePath: relativePath))
    }

    static func fileExists(relativePath: String?) -> Bool {
        guard let relativePath, !relativePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(relativePath: relativePath).path)
    }

    static func remove(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(relativePath: relativePath))
    }

    static func removeTree(relativePath: String) {
        try? FileManager.default.removeItem(at: url(relativePath: relativePath))
    }

    static func jpegData(from source: Data, maxPixel: CGFloat = 1600, quality: CGFloat = 0.72) -> (data: Data, width: Double, height: Double)? {
        guard let image = UIImage(data: source) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longest = max(size.width, size.height)
        let scale = longest > maxPixel ? maxPixel / longest : 1
        let target = CGSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = rendered.jpegData(compressionQuality: quality) else { return nil }
        return (data, Double(target.width), Double(target.height))
    }

    static func saveJPEG(_ source: Data, relativePath: String) throws -> (path: String, width: Double, height: Double) {
        guard let jpeg = jpegData(from: source) else { throw SandboxError.unreadableImage }
        try write(jpeg.data, relativePath: relativePath)
        return (relativePath, jpeg.width, jpeg.height)
    }

    /// Crops a local page JPEG. Nearly full-page or tiny boxes fall back to a copy of the page.
    static func cropJPEG(from sourcePath: String, normalizedTopLeft rect: CGRect, destination: String) throws {
        let clamped = PrintedQuestionSegmenter.clampUnit(rect)
        let nearlyFull = clamped.width >= 0.98 && clamped.height >= 0.98
        let tooSmall = clamped.width < 0.02 || clamped.height < 0.02
        if nearlyFull || tooSmall {
            try copyFile(from: sourcePath, to: destination)
            return
        }
        guard let image = loadUIImage(relativePath: sourcePath) else { throw SandboxError.unreadableImage }
        let crop = CGRect(
            x: clamped.origin.x * image.size.width,
            y: clamped.origin.y * image.size.height,
            width: clamped.width * image.size.width,
            height: clamped.height * image.size.height
        ).integral
        guard crop.width >= 1, crop.height >= 1 else {
            try copyFile(from: sourcePath, to: destination)
            return
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
        let rendered = renderer.image { _ in
            image.draw(
                in: CGRect(
                    x: -crop.origin.x,
                    y: -crop.origin.y,
                    width: image.size.width,
                    height: image.size.height
                )
            )
        }
        guard let data = rendered.jpegData(compressionQuality: 0.72) else { throw SandboxError.unreadableImage }
        try write(data, relativePath: destination)
    }

    static func copyFile(from sourcePath: String, to destinationPath: String) throws {
        let source = url(relativePath: sourcePath)
        let destination = url(relativePath: destinationPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    static func loadUIImage(relativePath: String?) -> UIImage? {
        guard let relativePath, let data = read(relativePath: relativePath) else { return nil }
        return UIImage(data: data)
    }
}
