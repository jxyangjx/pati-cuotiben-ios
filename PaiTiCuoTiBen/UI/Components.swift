import SwiftUI

struct StatusChip: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct SectionHeading: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnswerComparison: View {
    var student: String
    var canonical: String
    var steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledBlock(title: "我的作答", text: student.isEmpty ? "（空）" : student, tint: Theme.wrong)
            labeledBlock(title: "系统标答", text: canonical.isEmpty ? "（空）" : canonical, tint: Theme.accent)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("解题步骤")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func labeledBlock(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct SandboxImage: View {
    var relativePath: String?
    var height: CGFloat = 120

    var body: some View {
        Group {
            if let image = SandboxStore.loadUIImage(relativePath: relativePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.paper
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct FlowErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "请处理后再继续",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("好", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func flowErrorAlert(_ message: Binding<String?>) -> some View {
        modifier(FlowErrorAlert(message: message))
    }
}

struct MissingRecord: View {
    var text: String

    var body: some View {
        ContentUnavailableView(text, systemImage: "questionmark.folder", description: Text("返回上一页即可。"))
            .paperBackground()
    }
}
