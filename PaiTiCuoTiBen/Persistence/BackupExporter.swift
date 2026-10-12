import Foundation

enum BackupExporter {
    struct Document: Codable {
        var format: String
        var version: Int
        var exportedAt: String
        var note: String
        var children: [ChildRecord]
        var jobs: [JobRecord]
        var wrongItems: [WrongRecord]
        var files: [String]
    }

    struct ChildRecord: Codable {
        var id: String
        var name: String
        var grade: String
        var createdAt: String
        var archivedAt: String?
    }

    struct JobRecord: Codable {
        var id: String
        var childID: String
        var grade: String
        var subject: String
        var answerContext: String
        var mode: String
        var status: String
        var teacherKeyFilename: String?
        var teacherKeyFormat: String?
        var createdAt: String
        var updatedAt: String
        var pages: [PageRecord]
        var questions: [QuestionRecord]
    }

    struct PageRecord: Codable {
        var id: String
        var order: Int
        var imageRelativePath: String
        var purged: Bool
    }

    struct QuestionRecord: Codable {
        var id: String
        var order: Int
        var pageID: String?
        var stemText: String
        var questionType: String
        var cropRelativePath: String?
        var studentRawOCR: String
        var studentConfirmed: String?
        var studentSnapshot: String
        var markHints: String?
        var canonicalText: String
        var canonicalSteps: [String]
        var canonicalExplanation: String
        var canonicalConfirmation: String
        var canonicalAuthority: String
        var canonicalConfidence: Double
        var sourceRefs: [String]
        var verdict: String
        var verdictAuthority: String
        var verdictLocked: Bool
    }

    struct WrongRecord: Codable {
        var id: String
        var childID: String
        var sourceQuestionID: String
        var sourceJobID: String
        var subject: String
        var grade: String
        var questionType: String
        var stemText: String
        var cropRelativePath: String?
        var studentAnswer: String
        var canonicalText: String
        var canonicalSteps: [String]
        var analysisStatus: String
        var points: [String]
        var avoidanceTips: [String]
        var createdAt: String
    }

    @MainActor
    static func makePackage(children: [Child], jobs: [LocalJob], wrongItems: [WrongItem]) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var filePaths = Set<String>()

        let childRecords = children.map { child in
            ChildRecord(
                id: child.id.uuidString,
                name: child.name,
                grade: child.gradeRaw,
                createdAt: iso(child.createdAt),
                archivedAt: child.archivedAt.map(iso)
            )
        }

        let jobRecords = jobs.map { job -> JobRecord in
            if let path = job.teacherKeyRelativePath { filePaths.insert(path) }
            let pages = job.sortedPages.map { page in
                if !page.purged { filePaths.insert(page.imageRelativePath) }
                return PageRecord(
                    id: page.id.uuidString,
                    order: page.order,
                    imageRelativePath: page.imageRelativePath,
                    purged: page.purged
                )
            }
            let questions = job.sortedQuestions.map { question in
                if let path = question.cropRelativePath { filePaths.insert(path) }
                return QuestionRecord(
                    id: question.id.uuidString,
                    order: question.order,
                    pageID: question.pageID?.uuidString,
                    stemText: question.stemText,
                    questionType: question.questionType,
                    cropRelativePath: question.cropRelativePath,
                    studentRawOCR: question.answer?.rawOCR ?? "",
                    studentConfirmed: question.answer?.userConfirmed,
                    studentSnapshot: question.answer?.snapshotText ?? "",
                    markHints: question.answer?.markHints,
                    canonicalText: question.canonicalAnswer?.text ?? "",
                    canonicalSteps: question.canonicalAnswer?.steps ?? [],
                    canonicalExplanation: question.canonicalAnswer?.explanation ?? "",
                    canonicalConfirmation: question.canonicalAnswer?.confirmationRaw ?? CanonicalConfirmation.pending.rawValue,
                    canonicalAuthority: question.canonicalAnswer?.authorityRaw ?? VerdictAuthority.none.rawValue,
                    canonicalConfidence: question.canonicalAnswer?.confidence ?? 0,
                    sourceRefs: question.canonicalAnswer?.sourceRefs ?? [],
                    verdict: question.verdict?.resultRaw ?? VerdictResult.pending.rawValue,
                    verdictAuthority: question.verdict?.authorityRaw ?? VerdictAuthority.none.rawValue,
                    verdictLocked: question.verdict?.locked ?? false
                )
            }
            return JobRecord(
                id: job.id.uuidString,
                childID: job.childID.uuidString,
                grade: job.gradeRaw,
                subject: job.subjectRaw,
                answerContext: job.answerContextRaw,
                mode: job.modeRaw,
                status: job.statusRaw,
                teacherKeyFilename: job.teacherKeyFilename,
                teacherKeyFormat: job.teacherKeyFormatRaw,
                createdAt: iso(job.createdAt),
                updatedAt: iso(job.updatedAt),
                pages: pages,
                questions: questions
            )
        }

        let wrongRecords = wrongItems.map { item in
            if let path = item.cropRelativePath { filePaths.insert(path) }
            return WrongRecord(
                id: item.id.uuidString,
                childID: item.childID.uuidString,
                sourceQuestionID: item.sourceQuestionID.uuidString,
                sourceJobID: item.sourceJobID.uuidString,
                subject: item.subjectRaw,
                grade: item.gradeRaw,
                questionType: item.questionType,
                stemText: item.stemText,
                cropRelativePath: item.cropRelativePath,
                studentAnswer: item.studentAnswerText,
                canonicalText: item.canonicalText,
                canonicalSteps: item.canonicalSteps,
                analysisStatus: item.analysisStatusRaw,
                points: item.points,
                avoidanceTips: item.avoidanceTips,
                createdAt: iso(item.createdAt)
            )
        }

        var entries: [ZipStore.Entry] = []
        var included: [String] = []
        for path in filePaths.sorted() {
            guard let data = SandboxStore.read(relativePath: path) else { continue }
            let name = "files/" + path
            entries.append(ZipStore.Entry(name: name, data: data))
            included.append(name)
        }

        let document = Document(
            format: "paiticuotiben.backup",
            version: 1,
            exportedAt: stamp,
            note: "拍题错题本本机备份。卸载 App 或清除数据后，需要靠这份备份自行留存。备份里没有云端对象存储链接。",
            children: childRecords,
            jobs: jobRecords,
            wrongItems: wrongRecords,
            files: included
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(document)
        entries.insert(ZipStore.Entry(name: "backup.json", data: json), at: 0)
        let readme = """
        拍题错题本备份
        导出时间：\(stamp)
        打开 backup.json 可查看孩子、作业和错题。files/ 下是当时仍在本机的图片和老师标答文件。
        """
        entries.append(ZipStore.Entry(name: "README.txt", data: Data(readme.utf8)))

        let archive = ZipStore.archive(entries: entries)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("拍题错题本备份-\(stamp.replacingOccurrences(of: ":", with: "-"))")
            .appendingPathExtension("zip")
        try archive.write(to: url, options: .atomic)
        return url
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
