import Foundation

struct SimilarCacheItem: Equatable {
    var stem: String
    var answer: String?
    var source: String
}

struct SimilarCacheFile: Equatable {
    var items: [SimilarCacheItem]
    var generatedAt: String

    static func key(wrongItemID: UUID, questionType: String, locale: String) -> String {
        "\(wrongItemID.uuidString)|\(questionType)|\(locale)"
    }

    static func normalized(_ items: [SimilarQuestionItem]) -> [SimilarCacheItem] {
        items.compactMap { item in
            let stem = item.stem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stem.isEmpty else { return nil }
            let answer = item.answer?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SimilarCacheItem(
                stem: stem,
                answer: (answer?.isEmpty == false) ? answer : nil,
                source: "generated"
            )
        }
    }

    func encode() -> String {
        let rows: [[String: Any]] = items.map { item in
            var row: [String: Any] = ["stem": item.stem, "source": "generated"]
            if let answer = item.answer, !answer.isEmpty {
                row["answer"] = answer
            }
            return row
        }
        let object: [String: Any] = ["items": rows, "generatedAt": generatedAt]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func decode(_ raw: String) -> SimilarCacheFile? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["items"] as? [[String: Any]],
              let generatedAt = object["generatedAt"] as? String,
              !generatedAt.isEmpty else {
            return nil
        }
        let items = rows.compactMap { row -> SimilarCacheItem? in
            guard let stem = row["stem"] as? String else { return nil }
            let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let answer = row["answer"] as? String
            let source = (row["source"] as? String) ?? "generated"
            guard source == "generated" else { return nil }
            return SimilarCacheItem(stem: trimmed, answer: answer, source: "generated")
        }
        guard items.count >= 2 else { return nil }
        return SimilarCacheFile(items: items, generatedAt: generatedAt)
    }
}

enum VariantLocale {
    static var current: String {
        Locale.preferredLanguages.first ?? "zh-Hans"
    }
}

enum VariantPractice {
    enum Outcome: Equatable {
        case ungraded
        case correct
        case incorrect
    }

    /// A local check only. A wrong variant attempt is not written to the wrong book.
    static func check(attempt: String, answer: String?) -> Outcome {
        guard let answer else { return .ungraded }
        let expected = GradingPolicy.normalizeAnswer(answer)
        guard !expected.isEmpty else { return .ungraded }
        let given = GradingPolicy.normalizeAnswer(attempt)
        guard !given.isEmpty else { return .incorrect }
        return given == expected ? .correct : .incorrect
    }
}
