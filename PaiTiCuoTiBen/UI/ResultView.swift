import SwiftData
import SwiftUI

struct ResultView: View {
    var jobID: UUID
    var onReview: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var jobs: [LocalJob]
    @Query private var wrongItems: [WrongItem]
    @State private var tab = 0
    @State private var groups: [SummaryGroup] = []
    @State private var summaryNote: String?

    private var job: LocalJob? { jobs.first { $0.id == jobID } }

    var body: some View {
        Group {
            if let job {
                content(job)
            } else {
                MissingRecord(text: "找不到这次结果")
            }
        }
        .navigationTitle("本次结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("重新核对", action: onReview)
            }
        }
    }

    private func content(_ job: LocalJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(job.subject.rawValue) · \(job.grade.rawValue)")
                        .font(.headline)
                    Text("系统先批。待确认的题会留在下面两页里，确认判错之后才进入错题本。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("结果视图", selection: $tab) {
                        Text("逐题解析").tag(0)
                        Text("分类总结").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if job.status != .completed {
                        Button("记为完成") {
                            try? JobPipeline.markCompleted(job: job, context: context)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .cardChrome()

                if tab == 0 {
                    questionList(job)
                } else {
                    groupList
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .task(id: signature(job)) {
            await loadGroups(job)
        }
    }

    private func questionList(_ job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(job.sortedQuestions) { question in
                questionCard(question)
            }
        }
    }

    private func questionCard(_ question: Question) -> some View {
        let verdict = question.verdict?.result ?? .pending
        let item = wrongItems.first { $0.sourceQuestionID == question.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("第 \(question.order + 1) 题 · \(question.questionType)")
                    .font(.headline)
                Spacer()
                StatusChip(title: verdict.title, color: Theme.color(for: verdict))
            }
            if let summary = question.alignmentSummary {
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(question.alignmentStatus == .failed ? Theme.pending : .secondary)
            }
            Text(question.stemText)
                .font(.subheadline)
            AnswerComparison(
                student: question.answer?.snapshotText ?? "",
                canonical: question.canonicalAnswer?.text ?? "",
                steps: question.canonicalAnswer?.steps ?? []
            )
            if verdict == .pending {
                Text("这题还在待确认，没有写入错题本。")
                    .font(.footnote)
                    .foregroundStyle(Theme.pending)
            } else if verdict == .wrong, let item {
                analysisBlock(item)
            } else if verdict == .correct {
                Text("这题判为正确，不进入错题本。")
                    .font(.footnote)
                    .foregroundStyle(Theme.correct)
            }
        }
        .cardChrome()
    }

    private func analysisBlock(_ item: WrongItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.analysisStatus.title)
                .font(.subheadline.weight(.semibold))
            if item.analysisStatus == .ready {
                ForEach(Array(item.points.enumerated()), id: \.offset) { _, point in
                    Text("错因 · \(point)")
                        .font(.footnote)
                }
                ForEach(Array(item.avoidanceTips.enumerated()), id: \.offset) { _, tip in
                    Text("避坑 · \(tip)")
                        .font(.footnote)
                }
                if !item.errorTags.isEmpty {
                    Text("错因标签 · \(item.errorTags.joined(separator: "、"))")
                        .font(.footnote)
                }
            } else if item.analysisStatus == .failed {
                Text("错因还没写出来。可以到错题本里重试。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("先看上面的作答对照。错因会补在这条记录上。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summaryNote {
                Text(summaryNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                Text("生成题目卡片之后，这里会按题型汇总。")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.questionType)
                        .font(.headline)
                    HStack {
                        StatusChip(title: "正确 \(group.correctCount)", color: Theme.correct)
                        StatusChip(title: "错误 \(group.wrongCount)", color: Theme.wrong)
                        StatusChip(title: "待确认 \(group.pendingCount)", color: Theme.pending)
                    }
                    ForEach(Array(group.bullets.enumerated()), id: \.offset) { _, bullet in
                        Text(bullet)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .cardChrome()
            }
        }
    }

    private func signature(_ job: LocalJob) -> String {
        job.sortedQuestions.map { question in
            "\(question.id.uuidString):\(question.verdict?.resultRaw ?? "")"
        }.joined(separator: "|")
    }

    private func loadGroups(_ job: LocalJob) async {
        let request = SummaryGroupsRequest(
            subject: job.subjectRaw,
            grade: job.gradeRaw,
            questions: job.sortedQuestions.map { question in
                SummaryQuestionInput(
                    questionType: question.questionType,
                    result: question.verdict?.result ?? .pending,
                    stemText: question.stemText
                )
            }
        )
        do {
            groups = try await session.inference.summaryGroups(request)
            summaryNote = session.inferenceMode == .live
                ? "分类总结来自推理网关，只上传了题干和判定结果。"
                : "分类总结来自本机离线桩。"
        } catch {
            groups = []
            summaryNote = "题型总结暂时没有生成。"
        }
    }
}
