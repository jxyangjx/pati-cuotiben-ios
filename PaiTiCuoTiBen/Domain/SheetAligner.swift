import CoreGraphics
import Foundation

/// Arabic question numbers used to align a question sheet with an answer sheet.
enum QuestionNumbers {
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return trimmed }
        let stripped = trimmed.drop(while: { $0 == "0" })
        return stripped.isEmpty ? "0" : String(stripped)
    }

    /// Reads a leading `1.` / `1、` / `（1）` marker. The remainder is the rest of that line.
    static func split(_ text: String) -> (number: String, rest: String)? {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        let pattern = #"^\s*(?:(\d{1,3})\s*[.、．)）]|[（(]\s*(\d{1,3})\s*[）)])\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(firstLine.startIndex..<firstLine.endIndex, in: firstLine)
        guard let match = regex.firstMatch(in: firstLine, range: range) else { return nil }
        func group(_ index: Int) -> String? {
            let found = match.range(at: index)
            guard found.location != NSNotFound, let swiftRange = Range(found, in: firstLine) else { return nil }
            let value = String(firstLine[swiftRange])
            return value.isEmpty ? nil : value
        }
        guard let rawNumber = group(1) ?? group(2) else { return nil }
        return (normalize(rawNumber), group(3) ?? "")
    }

    static func number(in text: String) -> String? {
        split(text)?.number
    }
}

enum MarkHints {
    static let unreliable = "疑似已批，自批痕迹不可靠"

    /// Check marks and crosses are a weak hint. They never become a verdict authority.
    static func detect(_ text: String) -> String? {
        let tokens = ["✓", "√", "✔", "✗", "×", "✘"]
        return tokens.contains(where: text.contains) ? unreliable : nil
    }
}

struct SheetSegment: Equatable {
    var number: String
    var text: String
    var crop: CGRect
    var confidence: Double
    var pageID: UUID
}

struct AlignedDraft: Equatable {
    var questionNumber: String
    var stem: String
    var studentAnswer: String
    var status: AlignmentStatus
    var code: AlignmentCode?
    var crop: CGRect
    var confidence: Double
    var pageID: UUID
    var markHint: String?
    var origin: QuestionOrigin
}

enum AlignmentCopy {
    static let missingQuestionStem = "（答题卡题号，题目页未找到）"
}

struct RealignCard: Equatable {
    var number: String
    var stem: String
    var answer: String
    var origin: QuestionOrigin
}

struct RealignResult: Equatable {
    var status: AlignmentStatus
    var code: AlignmentCode?
}

/// Pairs question-sheet blocks with answer-sheet blocks by normalized question number.
enum SheetAligner {
    static func questionSegment(stem: String, crop: CGRect, confidence: Double, pageID: UUID) -> SheetSegment {
        let number = QuestionNumbers.number(in: stem) ?? ""
        return SheetSegment(
            number: number,
            text: stem.trimmingCharacters(in: .whitespacesAndNewlines),
            crop: crop,
            confidence: confidence,
            pageID: pageID
        )
    }

    static func answerSegment(block: String, crop: CGRect, confidence: Double, pageID: UUID) -> SheetSegment {
        let lines = block.components(separatedBy: "\n")
        let first = lines.first ?? ""
        if let split = QuestionNumbers.split(first) {
            let rest = ([split.rest] + lines.dropFirst())
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SheetSegment(number: split.number, text: rest, crop: crop, confidence: confidence, pageID: pageID)
        }
        return SheetSegment(
            number: "",
            text: block.trimmingCharacters(in: .whitespacesAndNewlines),
            crop: crop,
            confidence: confidence,
            pageID: pageID
        )
    }

    static func align(questions: [SheetSegment], answers: [SheetSegment]) -> [AlignedDraft] {
        let questionCounts = tally(questions)
        let answerCounts = tally(answers)
        var consumed = Set<Int>()
        var drafts: [AlignedDraft] = []

        for question in questions {
            if question.number.isEmpty || question.text.isEmpty {
                drafts.append(card(
                    question,
                    status: .failed,
                    code: .unreadable,
                    stem: question.text,
                    answer: "",
                    origin: .questionSheet,
                    hint: nil
                ))
                continue
            }
            let conflict = questionCounts[question.number, default: 0] > 1 || answerCounts[question.number, default: 0] > 1
            if conflict {
                drafts.append(card(
                    question,
                    status: .failed,
                    code: .ambiguousNumber,
                    stem: question.text,
                    answer: "",
                    origin: .questionSheet,
                    hint: nil
                ))
                continue
            }
            if let index = answers.firstIndex(where: { $0.number == question.number && !$0.text.isEmpty }) {
                consumed.insert(index)
                let answer = answers[index]
                drafts.append(AlignedDraft(
                    questionNumber: question.number,
                    stem: question.text,
                    studentAnswer: answer.text,
                    status: .matched,
                    code: nil,
                    crop: question.crop,
                    confidence: min(question.confidence, answer.confidence),
                    pageID: question.pageID,
                    markHint: MarkHints.detect(answer.text),
                    origin: .both
                ))
            } else {
                drafts.append(card(
                    question,
                    status: .failed,
                    code: .missingAnswer,
                    stem: question.text,
                    answer: "",
                    origin: .questionSheet,
                    hint: nil
                ))
            }
        }

        for (index, answer) in answers.enumerated() where !consumed.contains(index) {
            if answer.number.isEmpty || answer.text.isEmpty {
                drafts.append(card(
                    answer,
                    status: .failed,
                    code: .unreadable,
                    stem: answer.text,
                    answer: "",
                    origin: .answerSheet,
                    hint: MarkHints.detect(answer.text)
                ))
                continue
            }
            let conflict = questionCounts[answer.number, default: 0] > 1 || answerCounts[answer.number, default: 0] > 1
            let code: AlignmentCode = conflict ? .ambiguousNumber : .missingQuestion
            let stem = code == .missingQuestion ? AlignmentCopy.missingQuestionStem : answer.text
            let student = code == .missingQuestion ? answer.text : ""
            drafts.append(card(
                answer,
                status: .failed,
                code: code,
                stem: stem,
                answer: student,
                origin: .answerSheet,
                hint: MarkHints.detect(answer.text)
            ))
        }
        return drafts
    }

    /// Recomputes alignment after the user edits a question number or the student answer.
    static func realign(_ cards: [RealignCard]) -> [RealignResult] {
        let numbers = cards.map { QuestionNumbers.normalize($0.number) }
        var counts: [String: Int] = [:]
        for number in numbers where !number.isEmpty {
            counts[number, default: 0] += 1
        }
        return zip(cards, numbers).map { card, number in
            let stem = card.stem.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = card.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if number.isEmpty || (stem.isEmpty && answer.isEmpty) {
                return RealignResult(status: .failed, code: .unreadable)
            }
            if counts[number, default: 0] > 1 {
                return RealignResult(status: .failed, code: .ambiguousNumber)
            }
            switch card.origin {
            case .answerSheet:
                let stemMissing = stem.isEmpty || stem == AlignmentCopy.missingQuestionStem
                if stemMissing {
                    return RealignResult(status: .failed, code: .missingQuestion)
                }
                if answer.isEmpty {
                    return RealignResult(status: .failed, code: .unreadable)
                }
                return RealignResult(status: .matched, code: nil)
            case .questionSheet, .both:
                if stem.isEmpty {
                    return RealignResult(status: .failed, code: .unreadable)
                }
                if answer.isEmpty {
                    return RealignResult(status: .failed, code: .missingAnswer)
                }
                return RealignResult(status: .matched, code: nil)
            }
        }
    }

    private static func tally(_ items: [SheetSegment]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items where !item.number.isEmpty && !item.text.isEmpty {
            counts[item.number, default: 0] += 1
        }
        return counts
    }

    private static func card(
        _ segment: SheetSegment,
        status: AlignmentStatus,
        code: AlignmentCode?,
        stem: String,
        answer: String,
        origin: QuestionOrigin,
        hint: String?
    ) -> AlignedDraft {
        AlignedDraft(
            questionNumber: segment.number,
            stem: stem,
            studentAnswer: answer,
            status: status,
            code: code,
            crop: segment.crop,
            confidence: segment.confidence,
            pageID: segment.pageID,
            markHint: hint,
            origin: origin
        )
    }
}
