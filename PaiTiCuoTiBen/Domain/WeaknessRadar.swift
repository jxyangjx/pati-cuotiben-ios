import Foundation

struct RadarSlice: Identifiable, Equatable {
    enum Kind: String, Equatable, CaseIterable {
        case subject
        case questionType
        case errorTag

        var title: String {
            switch self {
            case .subject: "学科"
            case .questionType: "题型"
            case .errorTag: "错因标签"
            }
        }
    }

    var kind: Kind
    var label: String
    var count: Int

    var id: String { "\(kind.rawValue)|\(label)" }
}

/// Counts locked wrong-book rows already stored on device. It does not invent a KnowledgeStat table.
enum WeaknessRadar {
    static let emptyMessage = "完成几次核对后才会出现薄弱项"

    static func slices(subjects: [String], questionTypes: [String], errorTags: [String]) -> [RadarSlice] {
        let hasRows = !subjects.isEmpty || !questionTypes.isEmpty
        guard hasRows else { return [] }
        return buckets(.subject, subjects) + buckets(.questionType, questionTypes) + buckets(.errorTag, errorTags)
    }

    static func slices(items: [WrongItem]) -> [RadarSlice] {
        slices(
            subjects: items.map(\.subjectRaw),
            questionTypes: items.map(\.questionType),
            errorTags: items.flatMap(\.errorTags)
        )
    }

    private static func buckets(_ kind: RadarSlice.Kind, _ labels: [String]) -> [RadarSlice] {
        var counts: [String: Int] = [:]
        for label in labels {
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            counts[text, default: 0] += 1
        }
        return counts.keys.sorted().map { label in
            RadarSlice(kind: kind, label: label, count: counts[label] ?? 0)
        }
    }
}
