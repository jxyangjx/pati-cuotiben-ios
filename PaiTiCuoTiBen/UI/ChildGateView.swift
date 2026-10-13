import SwiftUI
import SwiftData

struct ChildGateView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Child.createdAt) private var children: [Child]
    @AppStorage(DefaultsKey.currentChildID) private var currentChildID = ""
    @State private var name = ""
    @State private var grade = GradeLevel.junior1
    @State private var errorMessage: String?

    private var archived: [Child] { children.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("拍题错题本")
                            .font(.largeTitle.weight(.semibold))
                        Text("作业照片和错题都留在这台手机上。先给一个孩子建立档案，之后可以再加，最多 5 个在学孩子。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        TextField("孩子的名字", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Picker("年级", selection: $grade) {
                            ForEach(GradeLevel.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        Button(action: create) {
                            Text("建立档案")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .cardChrome()

                    if !archived.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("已归档")
                                .font(.headline)
                            ForEach(archived) { child in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(child.name)
                                        Text(child.grade.rawValue)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("恢复") { restore(child) }
                                }
                            }
                        }
                        .cardChrome()
                    }
                }
                .padding(20)
            }
            .paperBackground()
            .flowErrorAlert($errorMessage)
        }
    }

    private func create() {
        do {
            let child = try JobPipeline.createChild(name: name, grade: grade, context: context)
            currentChildID = child.id.uuidString
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func restore(_ child: Child) {
        do {
            try JobPipeline.restore(child, context: context)
            currentChildID = child.id.uuidString
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
