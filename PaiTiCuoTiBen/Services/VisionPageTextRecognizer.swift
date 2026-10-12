import CoreGraphics
import Foundation
import UIKit
import Vision

/// Reads printed text from a page image that already lives on this device.
protocol PageTextRecognizing {
    func recognize(imageData: Data) async throws -> [OCRLine]
}

/// Apple Vision printed-text OCR. Accurate level, Chinese and English. No network and no handwriting request.
struct VisionPageTextRecognizer: PageTextRecognizing {
    func recognize(imageData: Data) async throws -> [OCRLine] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw SandboxError.unreadableImage
        }
        let orientation = cgOrientation(image.imageOrientation)
        do {
            return try await perform(
                cgImage: cgImage,
                orientation: orientation,
                languages: ["zh-Hans", "en-US"]
            )
        } catch {
            return try await perform(cgImage: cgImage, orientation: orientation, languages: nil)
        }
    }

    private func perform(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        languages: [String]?
    ) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    gate.resume { continuation.resume(throwing: error) }
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> OCRLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return OCRLine(
                        text: text,
                        boundingBox: observation.boundingBox,
                        confidence: Double(candidate.confidence)
                    )
                }
                gate.resume { continuation.resume(returning: lines) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let languages, !languages.isEmpty {
                request.recognitionLanguages = languages
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                gate.resume { continuation.resume(throwing: error) }
            }
        }
    }
}

/// `perform` and the Vision completion can both try to resume the same continuation.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        body()
    }
}

private func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up:
        .up
    case .down:
        .down
    case .left:
        .left
    case .right:
        .right
    case .upMirrored:
        .upMirrored
    case .downMirrored:
        .downMirrored
    case .leftMirrored:
        .leftMirrored
    case .rightMirrored:
        .rightMirrored
    @unknown default:
        .up
    }
}
