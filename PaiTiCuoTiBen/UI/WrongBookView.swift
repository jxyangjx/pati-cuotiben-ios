import SwiftData
import SwiftUI

private enum WrongRoute: Hashable {
    case detail(UUID)
}

struct WrongBookView: View {
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query(sort: \WrongItem.createdAt, order: .reverse) private var items: [WrongItem]
    @AppStorage(DefaultsKey.currentChildID) private var currentChildID = ""
    @State private var subjectFilter = "全部"
    @State private var path: [WrongRoute] = []

    private var currentChild: Child? {
        ChildSelection.current(among: children, storedID: currentChildID)
    }

    private var childItems: [WrongItem] {
        guard let currentChild else { return [] }
        return items.filter { $0.childID == currentChild.id }
    }

    private var subjects: [String] {
        let names = Set(childItems.map(\.subjectRaw))
        return ["全部"] + names.sorted()
    }

    private var visibleItems: [WrongItem] {
        guard subjectFilter != "全部" else { return childItems }
        return childItems.filter { $0.subjectRaw == subjectFilter }
    }

    var body: some View {
        NavigationStack(path: $path) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(
                    title: currentChild?.name ?? "错题本",
                    subtitle: "只收录已经确认判错的题。左边是当时的作答，右边是已确认的系统标答。"
                )
                if childItems.isEmpty {
                    Text("错题本还是空的。核对时把一题判错，并确认标答之后，它会出现在这里。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardChrome()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(subjects, id: \.self) { subject in
                                Button(subject) { subjectFilter = subject }
                                    .buttonStyle(.bordered)
                                    .tint(subject == subjectFilter ? Theme.accent : .secondary)
                            }
                        }
                    }
                    ForEach(visibleItems) { item in
                        Button {
                            path.append(.detail(item.id))
                        } label: {
                            wrongRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle("错题本")
        .navigationDestination(for: WrongRoute.self) { route in
            switch route {
            case .detail(let id):
                WrongItemDetailView(itemID: id)
            }
        }
        }
    }

    private func wrongRow(_ item: WrongItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(item.subject.rawValue) · \(item.questionType)")
                    .font(.headline)
                Spacer()
                StatusChip(title: item.analysisStatus.title, color: Theme.accent)
            }
            Text(item.stemText)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Text(item.createdAt.chineseStamp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardChrome()
    }
}

struct WrongItemDetailView: View {
    var itemID: UUID

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var items: [WrongItem]
    @State private var working = false

    private var item: WrongItem? { items.first { $0.id == itemID } }

    var body: some View {
        Group {
            if let item {
                detail(item)
            } else {
                MissingRecord(text: "这道错题已经不在了")
            }
        }
        .navigationTitle("错题")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ item: WrongItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(item.subject.rawValue) · \(item.grade.rawValue) · \(item.questionType)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.stemText)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardChrome()

                if item.cropRelativePath != nil {
                    SandboxImage(relativePath: item.cropRelativePath, height: 180)
                }

                AnswerComparison(
                    student: item.studentAnswerText,
                    canonical: item.canonicalText,
                    steps: item.canonicalSteps
                )
                .cardChrome()

                analysis(item)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
    }

    private func analysis(_ item: WrongItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.analysisStatus.title)
                .font(.headline)
            switch item.analysisStatus {
            case .pending:
                Text("作答对照已经在上面。错因和避坑建议生成后会补在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .ready:
                ForEach(Array(item.points.enumerated()), id: \.offset) { index, point in
                    Text("错因 \(index + 1). \(point)")
                        .font(.subheadline)
                }
                ForEach(Array(item.avoidanceTips.enumerated()), id: \.offset) { index, tip in
                    Text("避坑 \(index + 1). \(tip)")
                        .font(.subheadline)
                }
            case .failed:
                Text("这次没有生成错因。可以再试一次。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if item.analysisStatus != .ready {
                Button(working ? "正在生成" : "生成错因") {
                    working = true
                    Task {
                        await JobPipeline.retryAnalysis(
                            item: item,
                            context: context,
                            inference: session.inference
                        )
                        working = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(working)
            }
        }
        .cardChrome()
    }
}
