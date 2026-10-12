import SwiftData
import SwiftUI

struct ReviewView: View {
    var jobID: UUID
    var threshold: Double
    var onShowResult: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var jobs: [LocalJob]
    @State private var busyID: UUID?
    @State private var errorMessage: String?

    private var job: LocalJob? { jobs.first { $0.id == jobID } }

    var body: some View {
        Group {
            if let job {
                content(job)
            } else {
                MissingRecord(text: "找不到这次作业")
            }
        }
        .navigationTitle("核对题目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("本次结果", action: onShowResult)
                    .disabled(job?.questions.isEmpty ?? true)
            }
        }
        .flowErrorAlert($errorMessage)
    }

    private func content(_ job: LocalJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(job)
                if job.sortedQuestions.isEmpty {
                    Text("还没有题目卡片。回到导入页，识别本机上的印刷文字。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(job.sortedQuestions) { question in
                        QuestionCardView(
                            question: question,
                            isBusy: busyID == question.id,
                            onCanonicalEdited: { touchCanonical(question, job: job) },
                            onConfirmCanonical: { run(question, job: job) { try await JobPipeline.confirmCanonical(question: question, job: job, context: context, inference: session.inference, threshold: threshold) } },
                            onMarkCorrect: { run(question, job: job) { try await JobPipeline.judge(question: question, job: job, result: .correct, context: context, inference: session.inference, threshold: threshold) } },
                            onMarkWrong: { run(question, job: job) { try await JobPipeline.judge(question: question, job: job, result: .wrong, context: context, inference: session.inference, threshold: threshold) } },
                            onMarkPending: { run(question, job: job) { try await JobPipeline.judge(question: question, job: job, result: .pending, context: context, inference: session.inference, threshold: threshold) } },
                            onRegrade: { run(question, job: job) { try await JobPipeline.reprocessEditedText(question: question, job: job, context: context, inference: session.inference, threshold: threshold) } }
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(job.subject.rawValue) · \(job.grade.rawValue)")
                .font(.headline)
            Text("题干和作答来自本机 Vision 印刷文字识别，可以直接改正。系统先批：有把握的客观题会直接锁定，其余保持待确认。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let filename = job.teacherKeyFilename {
                Text("已挂上老师标答「\(filename)」。最终答案可以和它对齐，解题步骤仍由系统生成。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if job.answerContext == .selfMark {
                Text("本份作业标记为含自批。批改痕迹只作提示。")
                    .font(.footnote)
                    .foregroundStyle(Theme.pending)
            }
        }
        .cardChrome()
    }

    private func touchCanonical(_ question: Question, job: LocalJob) {
        try? JobPipeline.invalidateCanonical(question: question, job: job, context: context)
    }

    private func run(_ question: Question, job: LocalJob, _ work: @escaping () async throws -> Void) {
        busyID = question.id
        Task {
            do {
                try await work()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            busyID = nil
        }
    }
}
