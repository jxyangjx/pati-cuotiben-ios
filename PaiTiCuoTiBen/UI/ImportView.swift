import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedImage(data: data)
        }
    }
}

struct ImportView: View {
    var jobID: UUID
    var onReady: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var jobs: [LocalJob]
    @AppStorage(DefaultsKey.lockThreshold) private var lockThreshold = GradingPolicy.defaultLockThreshold

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showTeacherPicker = false
    @State private var replacementPageID: UUID?
    @State private var replacementItem: PhotosPickerItem?
    @State private var working = false
    @State private var errorMessage: String?
    @State private var skipNotice: SkipNotice?
    @State private var incomingRole: PageRole = .questionSheet

    private var job: LocalJob? { jobs.first { $0.id == jobID } }

    var body: some View {
        Group {
            if let job {
                form(job)
            } else {
                MissingRecord(text: "这份草稿已经不在了")
            }
        }
        .navigationTitle("导入页面")
        .navigationBarTitleDisplayMode(.inline)
        .flowErrorAlert($errorMessage)
        .alert(
            "有页面被跳过",
            isPresented: Binding(
                get: { skipNotice != nil },
                set: { if !$0 { skipNotice = nil } }
            ),
            presenting: skipNotice
        ) { _ in
            Button("继续核对", action: onReady)
        } message: { notice in
            Text(notice.text)
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in
                guard let job else { return }
                addImages([data], to: job)
            }
        }
        .fileImporter(
            isPresented: $showTeacherPicker,
            allowedContentTypes: Self.teacherTypes,
            allowsMultipleSelection: false
        ) { result in
            guard let job else { return }
            importTeacherKey(result, job: job)
        }
        .onChange(of: pickerItems) { _, items in
            guard let job, !items.isEmpty else { return }
            Task { await importPickerItems(items, job: job) }
        }
        .onChange(of: replacementItem) { _, item in
            guard let job, let item, let pageID = replacementPageID else { return }
            Task { await replace(item, pageID: pageID, job: job) }
        }
    }

    private func form(_ job: LocalJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard(job)
                teacherCard(job)
                pagesCard(job)
            }
            .padding(20)
            .padding(.bottom, 72)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button(action: { generate(job) }) {
                    Text(job.questions.isEmpty ? "生成题目卡片" : "重新生成题目卡片")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(job.sortedPages.isEmpty || working || (job.mode == .b && !modeBReady(job)))
                if working {
                    ProgressView(session.inferenceMode == .live ? "正在识别印刷文字，并向网关请求标答" : "正在识别本机上的印刷文字")
                        .font(.caption)
                } else if job.mode == .b && !modeBReady(job) {
                    Text("模式 B 至少需要一页题目页和一页答题卡。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if job.sortedPages.isEmpty {
                    Text("至少需要一页。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !job.questions.isEmpty {
                    Text("重新生成会覆盖这批题目卡片，以及它们已经进入错题本的记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func infoCard(_ job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "当次信息",
                subtitle: "年级、学科每次都要确认。模式 A 是同页作答；模式 B 先选题目页，再选答题卡。"
            )
            Picker("题目模式", selection: modeBinding(job)) {
                ForEach(JobMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(job.mode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("年级", selection: gradeBinding(job)) {
                ForEach(GradeLevel.allCases) { grade in
                    Text(grade.rawValue).tag(grade)
                }
            }
            Picker("学科", selection: subjectBinding(job)) {
                ForEach(Subject.allCases) { subject in
                    Text(subject.rawValue).tag(subject)
                }
            }
            Picker("答案情境", selection: contextBinding(job)) {
                ForEach(AnswerContext.allCases) { context in
                    Text(context.title).tag(context)
                }
            }
            Text(job.answerContext.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardChrome()
    }

    private func teacherCard(_ job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "老师标答（可选）",
                subtitle: "优先级是 Word、图片、PDF。能解析的文字只用来对齐最终答案，解题步骤仍由系统生成。解析失败可以换 docx 或图片。老师稿不作为判分权威。"
            )
            if job.teacherKeyStatus == .parsed {
                Text("已解析出老师标答文字，生成卡片时会用来对齐最终答案。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if job.teacherKeyStatus == .failed, !job.teacherKeyNote.isEmpty {
                Text(job.teacherKeyNote)
                    .font(.footnote)
                    .foregroundStyle(Theme.pending)
            } else if job.teacherKeyStatus == .pending {
                Text("图片会在生成题目卡片时在本机识别。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let filename = job.teacherKeyFilename {
                Text(filename)
                    .font(.subheadline.weight(.semibold))
                Text(job.teacherKeyFormat?.title ?? "已保存")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("移除", role: .destructive) {
                    try? JobPipeline.removeTeacherKey(job: job, context: context)
                }
            } else {
                Button("选择老师标答文件") { showTeacherPicker = true }
                    .buttonStyle(.bordered)
            }
        }
        .cardChrome()
    }

    private func pagesCard(_ job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "页面",
                subtitle: job.mode == .b
                    ? "先添加题目页，再添加答题卡。可以拖到另一页上调整顺序，也可以改每一页的角色。"
                    : "按阅读顺序排列。识别只读取保存在本机的印刷文字。可以重拍、替换或删掉某一页。"
            )
            if job.mode == .b {
                Picker("接下来添加", selection: $incomingRole) {
                    Text("题目页").tag(PageRole.questionSheet)
                    Text("答题卡").tag(PageRole.answerSheet)
                }
                .pickerStyle(.segmented)
            }
            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label(cameraTitle(job), systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label(albumTitle(job), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            ForEach(job.sortedPages) { page in
                pageRow(page, job: job)
            }
        }
        .cardChrome()
    }

    private func pageRow(_ page: Page, job: LocalJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第 \(page.order + 1) 页")
                    .font(.subheadline.weight(.semibold))
                if job.mode == .b {
                    Text(page.role.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if job.mode == .b {
                Picker("页面角色", selection: roleBinding(page, job: job)) {
                    Text("题目页").tag(PageRole.questionSheet)
                    Text("答题卡").tag(PageRole.answerSheet)
                }
                .pickerStyle(.segmented)
            }
            SandboxImage(relativePath: page.purged ? nil : page.imageRelativePath, height: 160)
            HStack {
                Button("上移") { shift(job: job, page: page, direction: -1) }
                    .disabled(page.order == 0)
                Button("下移") { shift(job: job, page: page, direction: 1) }
                    .disabled(page.order == job.sortedPages.count - 1)
                PhotosPicker(
                    selection: Binding(
                        get: { replacementPageID == page.id ? replacementItem : nil },
                        set: { newValue in
                            replacementPageID = page.id
                            replacementItem = newValue
                        }
                    ),
                    matching: .images
                ) {
                    Text("替换")
                }
                Spacer()
                Button("删除", role: .destructive) {
                    try? JobPipeline.deletePage(job: job, pageID: page.id, context: context)
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .draggable(page.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let source = UUID(uuidString: raw) else { return false }
            try? JobPipeline.movePage(job: job, pageID: source, before: page.id, context: context)
            return true
        }
    }

    private func cameraTitle(_ job: LocalJob) -> String {
        guard job.mode == .b else { return "拍照" }
        return incomingRole == .answerSheet ? "拍答题卡" : "拍题目页"
    }

    private func albumTitle(_ job: LocalJob) -> String {
        guard job.mode == .b else { return "相册" }
        return incomingRole == .answerSheet ? "答题卡相册" : "题目页相册"
    }

    private func modeBReady(_ job: LocalJob) -> Bool {
        job.sortedPages.contains { $0.role == .questionSheet } && job.sortedPages.contains { $0.role == .answerSheet }
    }

    private func gradeBinding(_ job: LocalJob) -> Binding<GradeLevel> {
        Binding(
            get: { job.grade },
            set: {
                job.grade = $0
                job.updatedAt = Date()
            }
        )
    }

    private func subjectBinding(_ job: LocalJob) -> Binding<Subject> {
        Binding(
            get: { job.subject },
            set: {
                job.subject = $0
                job.updatedAt = Date()
            }
        )
    }

    private func modeBinding(_ job: LocalJob) -> Binding<JobMode> {
        Binding(
            get: { job.mode },
            set: { mode in
                incomingRole = .questionSheet
                try? JobPipeline.setMode(job: job, mode: mode, context: context)
            }
        )
    }

    private func roleBinding(_ page: Page, job: LocalJob) -> Binding<PageRole> {
        Binding(
            get: { page.role },
            set: { role in
                try? JobPipeline.setPageRole(page: page, job: job, role: role, context: context)
            }
        )
    }

    private func contextBinding(_ job: LocalJob) -> Binding<AnswerContext> {
        Binding(
            get: { job.answerContext },
            set: {
                job.answerContext = $0
                job.updatedAt = Date()
            }
        )
    }

    private func addImages(_ datas: [Data], to job: LocalJob) {
        let role = job.mode == .b ? incomingRole : PageRole.questionSheet
        do {
            for data in datas {
                try JobPipeline.addPage(job: job, imageData: data, context: context, role: role)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func importPickerItems(_ items: [PhotosPickerItem], job: LocalJob) async {
        let role = job.mode == .b ? incomingRole : PageRole.questionSheet
        var failed = 0
        for item in items {
            if let image = try? await item.loadTransferable(type: ImportedImage.self) {
                do {
                    try JobPipeline.addPage(job: job, imageData: image.data, context: context, role: role)
                } catch {
                    failed += 1
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            } else {
                failed += 1
            }
        }
        pickerItems = []
        if failed > 0 && errorMessage == nil {
            errorMessage = "有 \(failed) 张图片没有导入，请换一张再试。"
        }
    }

    private func replace(_ item: PhotosPickerItem, pageID: UUID, job: LocalJob) async {
        defer {
            replacementItem = nil
            replacementPageID = nil
        }
        guard let page = job.pages.first(where: { $0.id == pageID }) else { return }
        guard let image = try? await item.loadTransferable(type: ImportedImage.self) else {
            errorMessage = "这张替换图片无法读取。"
            return
        }
        do {
            try JobPipeline.replacePage(page, job: job, imageData: image.data, context: context)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shift(job: LocalJob, page: Page, direction: Int) {
        try? JobPipeline.shiftPage(job: job, pageID: page.id, direction: direction, context: context)
    }

    private func generate(_ job: LocalJob) {
        working = true
        Task {
            do {
                let outcome = try await JobPipeline.recognizePages(
                    job: job,
                    context: context,
                    inference: session.inference,
                    threshold: lockThreshold
                )
                working = false
                if outcome.emptyPageNumbers.isEmpty {
                    onReady()
                } else {
                    let pages = outcome.emptyPageNumbers.map(String.init).joined(separator: "、")
                    let text = "第 \(pages) 页没有识别到印刷文字，已跳过。其余页面已生成题目卡片。"
                    session.notice = text
                    skipNotice = SkipNotice(text: text)
                }
            } catch {
                working = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func importTeacherKey(_ result: Result<[URL], Error>, job: LocalJob) {
        switch result {
        case .failure:
            errorMessage = "没有读到老师标答文件。请重试，或改用 docx / 图片。"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try JobPipeline.importTeacherKey(
                    job: job,
                    filename: url.lastPathComponent,
                    data: data,
                    context: context
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private static var teacherTypes: [UTType] {
        var types: [UTType] = [.image, .pdf, .data]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") {
            types.insert(docx, at: 0)
        }
        if let doc = UTType("com.microsoft.word.doc") {
            types.append(doc)
        }
        return types
    }
}

private struct SkipNotice: Identifiable {
    let id = UUID()
    let text: String
}

struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (Data) -> Void
        var dismiss: DismissAction

        init(onCapture: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
