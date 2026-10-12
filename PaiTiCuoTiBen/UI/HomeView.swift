import SwiftUI
import SwiftData

private enum HomeRoute: Hashable {
    case importer(UUID)
    case review(UUID)
    case result(UUID)
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query(sort: \LocalJob.createdAt, order: .reverse) private var jobs: [LocalJob]
    @AppStorage(DefaultsKey.currentChildID) private var currentChildID = ""
    @AppStorage(DefaultsKey.lockThreshold) private var lockThreshold = GradingPolicy.defaultLockThreshold
    @State private var path: [HomeRoute] = []
    @State private var showSwitcher = false
    @State private var pendingSwitchID: UUID?
    @State private var pendingDeleteID: UUID?
    @State private var errorMessage: String?

    private var currentChild: Child? {
        ChildSelection.current(among: children, storedID: currentChildID)
    }

    private var childJobs: [LocalJob] {
        guard let currentChild else { return [] }
        return jobs.filter { $0.childID == currentChild.id }
    }

    private var draftCount: Int {
        jobs.filter { $0.status == .draft }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let notice = session.notice {
                    Text(notice)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.pending.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let currentChild {
                    header(currentChild)
                    startCard
                    recentSection
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle("拍题错题本")
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .importer(let id):
                ImportView(jobID: id) {
                    path.append(.review(id))
                }
            case .review(let id):
                ReviewView(jobID: id, threshold: lockThreshold) {
                    path.append(.result(id))
                }
            case .result(let id):
                ResultView(jobID: id, onReview: {
                    path.append(.review(id))
                })
            }
        }
        .sheet(isPresented: $showSwitcher) {
            ChildSwitcherSheet(
                children: children.filter { !$0.isArchived },
                currentID: currentChild?.id,
                onSelect: requestSwitch
            )
        }
        .confirmationDialog(
            "切换孩子",
            isPresented: Binding(
                get: { pendingSwitchID != nil },
                set: { if !$0 { pendingSwitchID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换并清除草稿", role: .destructive) {
                if let pendingSwitchID {
                    currentChildID = pendingSwitchID.uuidString
                }
                pendingSwitchID = nil
            }
            Button("取消", role: .cancel) { pendingSwitchID = nil }
        } message: {
            Text("切换后，尚未生成题目卡片的上传草稿会被清掉，避免把页面带到另一个孩子名下。")
        }
        .flowErrorAlert($errorMessage)
        .confirmationDialog(
            "删除这次作业？",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDeleteID, let job = jobs.first(where: { $0.id == pendingDeleteID }) {
                    JobPipeline.deleteJob(job, context: context)
                    try? context.save()
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("页面会从本机删除。已经写入错题本的题目会留下。")
        }
        }
    }

    private func header(_ child: Child) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(child.name)
                    .font(.title2.weight(.semibold))
                Text("\(child.grade.rawValue) · 模式 A · 本机保存")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("切换") { showSwitcher = true }
                .buttonStyle(.bordered)
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "整理一份作业",
                subtitle: "一次导入多页。题目和手写答案在同一页，系统先给出标答，你再核对。"
            )
            Button(action: startImport) {
                Label("开始导入", systemImage: "doc.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .cardChrome()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "最近的作业", subtitle: childJobs.isEmpty ? "还没有记录。" : nil)
            if childJobs.isEmpty {
                Text("导入之后，草稿、待核对和已完成的作业会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(childJobs) { job in
                    jobRow(job)
                }
            }
        }
    }

    private func jobRow(_ job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(job.subject.rawValue) · \(job.grade.rawValue)")
                    .font(.headline)
                Spacer()
                StatusChip(title: job.status.title, color: Theme.accent)
            }
            Text("\(job.createdAt.chineseStamp) · \(job.sortedPages.count) 页 · \(job.sortedQuestions.count) 题")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button(job.status == .draft ? "继续导入" : (job.status == .completed ? "查看结果" : "继续核对")) {
                    open(job)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("删除", role: .destructive) {
                    pendingDeleteID = job.id
                }
                .font(.subheadline)
            }
        }
        .cardChrome()
    }

    private func open(_ job: LocalJob) {
        switch job.status {
        case .draft:
            path.append(.importer(job.id))
        case .reviewing:
            path.append(.review(job.id))
        case .completed:
            path.append(.result(job.id))
        }
    }

    private func startImport() {
        guard let currentChild else { return }
        do {
            let job = try JobPipeline.createDraft(
                child: currentChild,
                grade: currentChild.grade,
                subject: .math,
                answerContext: .student,
                context: context
            )
            path.append(.importer(job.id))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func requestSwitch(_ child: Child) {
        showSwitcher = false
        guard child.id.uuidString != currentChildID else { return }
        if draftCount > 0 {
            pendingSwitchID = child.id
        } else {
            currentChildID = child.id.uuidString
        }
    }
}

private struct ChildSwitcherSheet: View {
    var children: [Child]
    var currentID: UUID?
    var onSelect: (Child) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(children) { child in
                Button {
                    onSelect(child)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(child.name)
                            Text(child.grade.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if child.id == currentID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("切换孩子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
