import SwiftUI

struct QuestionCardView: View {
    @Bindable var question: Question
    var isBusy: Bool
    var showsAlignment: Bool = false
    var onCanonicalEdited: () -> Void
    var onConfirmCanonical: () -> Void
    var onMarkCorrect: () -> Void
    var onMarkWrong: () -> Void
    var onMarkPending: () -> Void
    var onRegrade: () -> Void
    var onRealign: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(showsAlignment && !question.questionNumber.isEmpty ? "题号 \(question.questionNumber)" : "第 \(question.order + 1) 题")
                    .font(.headline)
                Spacer()
                if let summary = question.alignmentSummary {
                    StatusChip(
                        title: summary,
                        color: question.alignmentStatus == .matched ? Theme.correct : Theme.pending
                    )
                }
                Text(question.questionType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let verdict = question.verdict {
                    StatusChip(title: verdict.result.title, color: Theme.color(for: verdict.result))
                }
            }

            if question.cropRelativePath != nil {
                SandboxImage(relativePath: question.cropRelativePath, height: 140)
            }

            if showsAlignment {
                alignmentSection
            }

            Text("题干")
                .font(.subheadline.weight(.semibold))
            TextField("题干", text: $question.stemText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            if !question.stemRawOCR.isEmpty, question.stemRawOCR != question.stemText {
                Text("识别原文：\(question.stemRawOCR)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if question.ocrConfidence > 0 {
                Text("印刷文字识别置信度 \(percent(question.ocrConfidence))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if question.ocrConfidence > 0, question.ocrConfidence < PrintedQuestionSegmenter.lowConfidenceThreshold {
                Text("识别置信度偏低，请对照原图改正题干和作答。")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.pending)
            }

            studentSection
            canonicalSection
            verdictSection
            actions
            if isBusy {
                ProgressView()
            }
        }
        .cardChrome()
    }

    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("题号")
                .font(.subheadline.weight(.semibold))
            TextField("题号", text: $question.questionNumber)
                .textFieldStyle(.roundedBorder)
            if question.alignmentStatus == .failed {
                Text("对齐失败，这题保持待确认。可以手改题号和作答，再重新对齐。")
                    .font(.caption)
                    .foregroundStyle(Theme.pending)
            }
            Button("按当前题号重新对齐", action: onRealign)
                .font(.subheadline)
                .disabled(isBusy)
        }
    }

    private var studentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("学生作答")
                .font(.subheadline.weight(.semibold))
            TextField("学生作答", text: studentBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            if let raw = question.answer?.rawOCR, raw != question.answer?.snapshotText {
                Text("识别原文：\(raw)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let hint = question.answer?.markHints, !hint.isEmpty {
                Text(hint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.pending)
            }
        }
    }

    @ViewBuilder
    private var canonicalSection: some View {
        if let canonical = question.canonicalAnswer {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(canonical.confirmation.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("置信度 \(percent(canonical.confidence))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if canonical.stepsNeedReview {
                    Text("步骤待确认")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.pending)
                }
                TextField("最终答案", text: canonicalTextBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                ForEach(Array(canonical.steps.enumerated()), id: \.offset) { index, _ in
                    HStack(alignment: .top) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        TextField("解题步骤", text: stepBinding(index), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if canonical.steps.count > 1 {
                            Button(role: .destructive) {
                                removeStep(index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("加一条步骤") { addStep() }
                    .font(.subheadline)
                if !canonical.explanation.isEmpty {
                    Text(canonical.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !canonical.sourceRefs.isEmpty {
                    Text("参考：\(canonical.sourceRefs.joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var verdictSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let verdict = question.verdict {
                if verdict.locked {
                    Text("已锁定 · \(verdict.authority.title)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let leaning = verdict.leaning {
                    Text("尚未锁定。模型倾向：\(leaning.title)。确认后才会写入错题本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未锁定。待确认的题不会进入错题本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("确认标答", action: onConfirmCanonical)
                .buttonStyle(.borderedProminent)
                .disabled(!canConfirm || isBusy)
            HStack {
                Button("判为正确", action: onMarkCorrect)
                Button("判为错误", action: onMarkWrong)
                Button("改回待确认", action: onMarkPending)
            }
            .buttonStyle(.bordered)
            .disabled(!canConfirm || isBusy)
            Button("按当前文字重新生成标答", action: onRegrade)
                .font(.subheadline)
                .disabled(isBusy)
        }
    }

    private var canConfirm: Bool {
        guard let canonical = question.canonicalAnswer else { return false }
        let text = canonical.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = canonical.steps.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !text.isEmpty && steps
    }

    private var studentBinding: Binding<String> {
        Binding(
            get: { question.answer?.userConfirmed ?? question.answer?.rawOCR ?? "" },
            set: { question.answer?.userConfirmed = $0 }
        )
    }

    private var canonicalTextBinding: Binding<String> {
        Binding(
            get: { question.canonicalAnswer?.text ?? "" },
            set: { newValue in
                guard let canonical = question.canonicalAnswer, canonical.text != newValue else { return }
                canonical.text = newValue
                onCanonicalEdited()
            }
        )
    }

    private func stepBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let steps = question.canonicalAnswer?.steps, steps.indices.contains(index) else { return "" }
                return steps[index]
            },
            set: { newValue in
                guard let canonical = question.canonicalAnswer else { return }
                var steps = canonical.steps
                guard steps.indices.contains(index), steps[index] != newValue else { return }
                steps[index] = newValue
                canonical.steps = steps
                onCanonicalEdited()
            }
        )
    }

    private func addStep() {
        guard let canonical = question.canonicalAnswer else { return }
        var steps = canonical.steps
        steps.append("")
        canonical.steps = steps
        onCanonicalEdited()
    }

    private func removeStep(_ index: Int) {
        guard let canonical = question.canonicalAnswer else { return }
        var steps = canonical.steps
        guard steps.indices.contains(index), steps.count > 1 else { return }
        steps.remove(at: index)
        canonical.steps = steps
        onCanonicalEdited()
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
