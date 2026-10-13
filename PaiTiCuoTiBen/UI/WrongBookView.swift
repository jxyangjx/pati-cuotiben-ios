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
                    subtitle: "只收录已经确认判错的题。左边是当时的作答，右边是已确认的系统标答。变式题只在已入库错题的详情里。"
                )
                radarCard
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

    private var radarCard: some View {
        let slices = WeaknessRadar.slices(items: childItems)
        return VStack(alignment: .leading, spacing: 10) {
            Text("薄弱雷达")
                .font(.headline)
            if slices.isEmpty {
                Text(WeaknessRadar.emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(RadarSlice.Kind.allCases, id: \.rawValue) { kind in
                    let rows = slices.filter { $0.kind == kind }
                    if !rows.isEmpty {
                        Text(kind.title)
                            .font(.subheadline.weight(.semibold))
                        ForEach(rows) { slice in
                            HStack {
                                Text(slice.label)
                                Spacer()
                                Text("\(slice.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .cardChrome()
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
    @State private var similarWorking = false
    @State private var similarFile: SimilarCacheFile?
    @State private var similarTask: Task<Void, Never>?
    @State private var attempts: [Int: String] = [:]
    @State private var outcomes: [Int: VariantPractice.Outcome] = [:]
    @State private var similarError: String?

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
                variants(item)
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
                if !item.errorTags.isEmpty {
                    Text("错因标签：\(item.errorTags.joined(separator: "、"))")
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

    private func variants(_ item: WrongItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("练一练")
                .font(.headline)
            Text("根据这道已入库错题生成 2 到 3 道变式。练错了不会写入错题本。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let similarFile {
                ForEach(Array(similarFile.items.enumerated()), id: \.offset) { index, variant in
                    variantRow(index: index, variant: variant)
                }
            }
            if let similarError {
                Text(similarError)
                    .font(.footnote)
                    .foregroundStyle(Theme.pending)
            }
            HStack {
                Button(similarWorking ? "正在生成" : (similarFile == nil ? "生成变式" : "重新生成")) {
                    startSimilar(item, replacing: similarFile != nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(similarWorking)
                if similarWorking {
                    Button("取消") {
                        similarTask?.cancel()
                        similarTask = nil
                        similarWorking = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .cardChrome()
        .onAppear {
            similarFile = JobPipeline.cachedSimilar(item: item, locale: VariantLocale.current)
        }
    }

    private func variantRow(index: Int, variant: SimilarCacheItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(variant.stem)
                .font(.subheadline)
            TextField("我的作答", text: attemptBinding(index))
                .textFieldStyle(.roundedBorder)
            Button("核对自己的作答") {
                outcomes[index] = VariantPractice.check(attempt: attempts[index] ?? "", answer: variant.answer)
            }
            .font(.subheadline)
            if let outcome = outcomes[index] {
                Text(outcomeText(outcome))
                    .font(.footnote)
                    .foregroundStyle(outcome == .incorrect ? Theme.pending : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func outcomeText(_ outcome: VariantPractice.Outcome) -> String {
        switch outcome {
        case .correct:
            "做对了。这道变式不会另记一笔。"
        case .incorrect:
            "这题练错了，不会写入错题本。"
        case .ungraded:
            "这道变式没有附答案，只供自己核对，不会写入错题本。"
        }
    }

    private func attemptBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { attempts[index] ?? "" },
            set: { attempts[index] = $0 }
        )
    }

    private func startSimilar(_ item: WrongItem, replacing: Bool) {
        similarError = nil
        similarWorking = true
        let locale = VariantLocale.current
        similarTask = Task {
            do {
                let file = try await JobPipeline.generateSimilar(
                    item: item,
                    context: context,
                    inference: session.inference,
                    locale: locale,
                    replacingCache: replacing
                )
                if Task.isCancelled {
                    similarWorking = false
                    return
                }
                similarFile = file
                attempts = [:]
                outcomes = [:]
            } catch is CancellationError {
                similarWorking = false
                return
            } catch {
                if !Task.isCancelled {
                    similarError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            similarWorking = false
            similarTask = nil
        }
    }
}
