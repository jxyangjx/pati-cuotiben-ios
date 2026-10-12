import Foundation

enum GradeLevel: String, CaseIterable, Identifiable, Codable {
    case primary1 = "一年级"
    case primary2 = "二年级"
    case primary3 = "三年级"
    case primary4 = "四年级"
    case primary5 = "五年级"
    case primary6 = "六年级"
    case junior1 = "七年级"
    case junior2 = "八年级"
    case junior3 = "九年级"
    case senior1 = "高一"
    case senior2 = "高二"
    case senior3 = "高三"

    var id: String { rawValue }

    static func resolve(_ raw: String) -> GradeLevel {
        GradeLevel(rawValue: raw) ?? .junior1
    }
}

enum Subject: String, CaseIterable, Identifiable, Codable {
    case chinese = "语文"
    case math = "数学"
    case english = "英语"
    case physics = "物理"
    case chemistry = "化学"
    case biology = "生物"
    case history = "历史"
    case geography = "地理"
    case civics = "道德与法治"
    case science = "科学"

    var id: String { rawValue }

    static func resolve(_ raw: String) -> Subject {
        Subject(rawValue: raw) ?? .math
    }
}

/// How handwriting on the page should be read. Mode A only.
enum AnswerContext: String, CaseIterable, Identifiable, Codable {
    case student
    case selfMark = "self_mark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: "学生作答"
        case .selfMark: "含自批"
        }
    }

    var detail: String {
        switch self {
        case .student:
            "题目下方的手写内容记为学生答案。"
        case .selfMark:
            "页面上有自批痕迹。痕迹只显示「疑似自批」，不会提高置信度，也不会成为判分权威。"
        }
    }

    static func resolve(_ raw: String) -> AnswerContext {
        AnswerContext(rawValue: raw) ?? .student
    }
}

enum JobMode: String, Codable {
    /// Question and handwritten answer on the same page.
    case a = "A"
}

enum JobStatus: String, Codable {
    case draft
    case reviewing
    case completed

    var title: String {
        switch self {
        case .draft: "草稿"
        case .reviewing: "待核对"
        case .completed: "已完成"
        }
    }

    static func resolve(_ raw: String) -> JobStatus {
        JobStatus(rawValue: raw) ?? .draft
    }
}

enum CanonicalConfirmation: String, Codable {
    case pending
    case confirmed

    var title: String {
        switch self {
        case .pending: "系统标答（待确认）"
        case .confirmed: "系统标答（已确认）"
        }
    }

    static func resolve(_ raw: String) -> CanonicalConfirmation {
        CanonicalConfirmation(rawValue: raw) ?? .pending
    }
}

enum VerdictResult: String, Codable, Equatable {
    case correct
    case wrong
    case pending

    var title: String {
        switch self {
        case .correct: "正确"
        case .wrong: "错误"
        case .pending: "待确认"
        }
    }

    static func resolve(_ raw: String) -> VerdictResult {
        switch raw {
        case "correct": .correct
        case "wrong": .wrong
        default: .pending
        }
    }
}

enum VerdictAuthority: String, Codable, Equatable {
    case userConfirm = "user_confirm"
    case autoCanonical = "auto_canonical"
    case autoObjective = "auto_objective"
    case none = "none"

    var title: String {
        switch self {
        case .userConfirm: "用户确认"
        case .autoCanonical: "系统高置信标答"
        case .autoObjective: "客观题自动判定"
        case .none: "未锁定"
        }
    }

    /// `teacher_key` and `self_mark` are intentionally dropped.
    static func resolve(_ raw: String) -> VerdictAuthority {
        switch raw {
        case Self.userConfirm.rawValue: .userConfirm
        case Self.autoCanonical.rawValue: .autoCanonical
        case Self.autoObjective.rawValue: .autoObjective
        default: .none
        }
    }
}

enum AnalysisStatus: String, Codable {
    case pending
    case ready
    case failed

    var title: String {
        switch self {
        case .pending: "错因分析中"
        case .ready: "错因已生成"
        case .failed: "错因分析失败"
        }
    }

    static func resolve(_ raw: String) -> AnalysisStatus {
        AnalysisStatus(rawValue: raw) ?? .pending
    }
}

enum TeacherKeyFormat: String, Codable {
    case docx
    case doc
    case image
    case pdf
    case unknown

    var title: String {
        switch self {
        case .docx: "Word（.docx）"
        case .doc: "Word（.doc）"
        case .image: "图片"
        case .pdf: "PDF"
        case .unknown: "未识别"
        }
    }

    static func detect(filename: String) -> TeacherKeyFormat {
        switch (filename as NSString).pathExtension.lowercased() {
        case "docx": .docx
        case "doc": .doc
        case "pdf": .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff": .image
        default: .unknown
        }
    }
}

enum CanonicalAdoption: Equatable {
    case none
    case user
    case auto
}

enum ChildPolicy {
    static let maxActive = 5

    static func canActivate(activeCount: Int) -> Bool {
        activeCount < maxActive
    }
}

enum AnalysisText {
    static func points(_ values: [String]) -> [String] {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(cleaned.prefix(3))
    }

    static func tips(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum AppError: LocalizedError, Equatable {
    case invalidName
    case childLimit
    case missingChild
    case missingJob
    case noPages
    case teacherKeyFormat
    case teacherKeyTooLarge
    case missingCanonical

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "请填写孩子的名字。"
        case .childLimit:
            "在学孩子最多 5 个。可以先归档一个，再添加。"
        case .missingChild:
            "找不到这个孩子的档案。"
        case .missingJob:
            "找不到这次作业。"
        case .noPages:
            "请至少导入一页作业。"
        case .teacherKeyFormat:
            "这份老师标答格式无法识别。请改用 docx 或图片。"
        case .teacherKeyTooLarge:
            "老师标答文件超过 30MB。请压缩，或改用图片。"
        case .missingCanonical:
            "系统标答需要最终答案，以及至少一条解题步骤。"
        }
    }
}
