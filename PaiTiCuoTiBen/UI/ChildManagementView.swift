import SwiftData
import SwiftUI

struct ChildManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Child.createdAt) private var children: [Child]
    @AppStorage(DefaultsKey.currentChildID) private var currentChildID = ""
    @State private var draft: ChildDraft?
    @State private var errorMessage: String?
    @State private var pendingDeleteID: UUID?

    private var activeCount: Int { children.filter { !$0.isArchived }.count }

    var body: some View {
        List {
            Section {
                Text("在学 \(activeCount) / \(ChildPolicy.maxActive)。归档后不占名额，错题仍留在本机，恢复后才能继续拍题。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("添加孩子") {
                    draft = ChildDraft(childID: nil, name: "", grade: .junior1)
                }
                .disabled(!ChildPolicy.canActivate(activeCount: activeCount))
            }

            Section("在学") {
                let active = children.filter { !$0.isArchived }
                if active.isEmpty {
                    Text("还没有在学的孩子。")
                }
                ForEach(active) { child in
                    childRow(child)
                }
            }

            Section("已归档") {
                let archived = children.filter(\.isArchived)
                if archived.isEmpty {
                    Text("没有归档档案。")
                        .foregroundStyle(.secondary)
                }
                ForEach(archived) { child in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(child.name)
                        Text(child.grade.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("恢复") { restore(child) }
                            .disabled(!ChildPolicy.canActivate(activeCount: activeCount))
                    }
                }
            }
        }
        .navigationTitle("孩子管理")
        .scrollContentBackground(.hidden)
        .paperBackground()
        .sheet(item: $draft) { draft in
            ChildEditorSheet(draft: draft) { name, grade in
                save(draft: draft, name: name, grade: grade)
            }
        }
        .confirmationDialog(
            "删除这个孩子的本机档案？",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除档案和本机错题", role: .destructive) {
                if let pendingDeleteID, let child = children.first(where: { $0.id == pendingDeleteID }) {
                    remove(child)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("该孩子的作业、页面和错题会从这台手机删除。")
        }
        .flowErrorAlert($errorMessage)
    }

    private func childRow(_ child: Child) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(child.name)
                    .font(.headline)
                if child.id.uuidString == currentChildID {
                    StatusChip(title: "当前", color: Theme.accent)
                }
            }
            Text(child.grade.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("编辑") {
                    draft = ChildDraft(childID: child.id, name: child.name, grade: child.grade)
                }
                Button("设为当前") { currentChildID = child.id.uuidString }
                Button("归档") { archive(child) }
                Button("删除", role: .destructive) { pendingDeleteID = child.id }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func save(draft: ChildDraft, name: String, grade: GradeLevel) {
        do {
            if let childID = draft.childID, let child = children.first(where: { $0.id == childID }) {
                try JobPipeline.updateChild(child, name: name, grade: grade, context: context)
            } else {
                let child = try JobPipeline.createChild(name: name, grade: grade, context: context)
                if currentChildID.isEmpty {
                    currentChildID = child.id.uuidString
                }
            }
            self.draft = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func archive(_ child: Child) {
        try? JobPipeline.archive(child, context: context)
    }

    private func restore(_ child: Child) {
        do {
            try JobPipeline.restore(child, context: context)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func remove(_ child: Child) {
        try? JobPipeline.deleteChild(child, context: context)
    }
}

struct ChildDraft: Identifiable {
    let id = UUID()
    var childID: UUID?
    var name: String
    var grade: GradeLevel
}

struct ChildEditorSheet: View {
    var draft: ChildDraft
    var onSave: (String, GradeLevel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var grade: GradeLevel

    init(draft: ChildDraft, onSave: @escaping (String, GradeLevel) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _grade = State(initialValue: draft.grade)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名字", text: $name)
                Picker("年级", selection: $grade) {
                    ForEach(GradeLevel.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
            }
            .navigationTitle(draft.childID == nil ? "添加孩子" : "编辑档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(name, grade) }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
