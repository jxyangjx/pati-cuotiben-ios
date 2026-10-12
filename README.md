# 拍题错题本 · iOS 一期

Phase-1 on-device iOS app for PRD v1.5. Homework photos, recognized text, system answers, and the wrong-book stay in the phone sandbox (SwiftData + files). There is no object storage, no Mode B answer-sheet flow, and no WeChat login.

## Open in Xcode

1. Use Xcode 15 or newer, with an iOS 17+ simulator.
2. Open `PaiTiCuoTiBen.xcodeproj`.
3. Select the `PaiTiCuoTiBen` scheme and an iPhone simulator.
4. Run. For a physical device, pick your development team in Signing & Capabilities. The simulator can run with local signing.
5. Run tests with Product → Test, or:

```bash
xcodebuild test -scheme PaiTiCuoTiBen -destination 'platform=iOS Simulator,name=iPhone 16'
```

Grading, the offline stub, and the job pipeline are covered without depending on Vision's reading of a photo. `VisionOCRTests` also draws a high-contrast `1 + 1 = 2` image and checks that on-device recognition sees a `1`.

## Verify in the simulator

1. Delete the app first if it was installed before, so the privacy screen appears again.
2. Launch. The first screen is the privacy consent. It states that the camera and photo library are **仅用于本人作业整理**, and that photos and text stay on this phone. Creating a child and the first grading pass stay blocked until you tap **同意并继续**.
3. Create a child (at most 5 active children).
4. Start a job, then import a printed worksheet from the photo library or the camera. Pages are saved only under the app sandbox.
5. Tap **生成题目卡片**. The progress line says the app is recognizing printed text on this device. A page with no printed text is skipped and named; if every page is empty, nothing is replaced.
6. On the review cards, check the stem, the student line, the crop, and the OCR confidence. Edit either text field. The original OCR line stays visible when it differs from the edited text. A confidence above 0 and below 0.5 asks you to correct the card. Confidence 0 means the value is unknown.
7. Tap **按当前文字重新生成标答**. That calls the on-device stub again from the current stem and student snapshot, then grades. Clearing the student field keeps the answer empty instead of restoring the raw OCR line.
8. Open **本次结果** for the per-question list and the summary by question type. A locked wrong answer appears in the wrong book with the student snapshot, canonical text, at least one step, and error analysis.
9. Settings → 隐私说明 repeats **仅用于本人作业整理**.

The camera and photo-library usage strings in `Info.plist` include the same phrase.

## What this build does

- Child profiles: create, edit, switch, archive, restore, delete. Switching children clears upload drafts that have not generated question cards yet.
- First-run privacy consent, stored locally, before `createChild` and before `recognizePages`.
- Mode A import: grade and subject are required, answer context is student handwriting or a self-mark hint, pages come from the photo library or the camera, and an optional teacher-key file (Word, image, or PDF) is copied into the sandbox.
- Printed-text OCR with Apple Vision (`VNRecognizeTextRequest`, accurate, `zh-Hans` and `en-US`) on the page JPEG already stored on device. Numbered lines (`1.` / `1、` / `（1）` / `一、`) start a question. The last line of a multi-line block is treated as the student answer. `1 + 1` does not start a new question.
- Review cards keep `stemRawOCR`, the editable stem, the editable student snapshot, OCR confidence, and a local crop. Low-confidence cuts stay on the card for correction.
- System grading. Confidence at or above the threshold (default 0.85, adjustable in Settings) can auto-lock an objective question. Below that, the card stays pending and is not written to the wrong book.
- Result page with two views: per-question breakdown, and a summary grouped by question type.
- Wrong book: confirmed wrong answers only, with the student snapshot, canonical text, at least one step, and error analysis (`pending` / `ready` / `failed`).
- Settings: privacy note, zip backup, 30-day original-page cleanup (wrong-book crops stay), and the usage note.

Verdict authority is only `user_confirm`, `auto_canonical`, or `auto_objective`. A teacher file is stored as `canonical_answer.source_refs`. Self-mark traces are a hint only.

## What is stubbed

| Piece | Current behavior |
| --- | --- |
| Handwriting OCR | Not a separate request. Printed text is recognized first. The answer line is the last line of the printed block and can be edited. |
| `POST /v1/inference/solve` | `StubInferenceClient` returns on-device text and steps. `1 + 1` is the high-confidence sample. |
| `POST /v1/inference/grade` | String compare on device. Empty answers stay pending. |
| `POST /v1/inference/error-analysis` | Fixed points and avoidance tips, clamped to 1–3 points. |
| `POST /v1/inference/summary-groups` | Groups the questions already stored on device. |
| Teacher key | The file is saved locally. Word / PDF text is not parsed, and it is not a grading authority. |
| Apple Sign-In | Not wired. Profiles are local. |
| Similar questions | Not in this phase. |

`InferenceClient` is the thin gateway. The stub never opens a network connection. Page images are not uploaded.

## Next milestones

1. **Real inference.** Add a remote `InferenceClient` for `/v1/inference/solve`, `/grade`, `/error-analysis`, and `/summary-groups`. Payloads are cropped text for that call only and are not stored on our servers.
2. **Word teacher key.** Parse `.docx` first, then images and PDF. Align the final answer with the teacher file when parsing works, and keep solution steps system-generated. Offer a retry with docx or an image when parsing fails.
3. **Handwriting recognition.** If the last-line answer heuristic is not enough, add a handwriting pass that still stays on device.

## Layout

```
PaiTiCuoTiBen.xcodeproj
PaiTiCuoTiBen/
  Domain/          grading rules, enums, printed-question segmenter
  Models/          Child, LocalJob, Page, Question, Answer, CanonicalAnswer, Verdict, WrongItem
  Persistence/     SwiftData, sandbox files, zip backup
  Inference/       InferenceClient + StubInferenceClient
  Services/        JobPipeline, VisionPageTextRecognizer
  UI/              privacy consent, child switcher, import, review, dual result, wrong book, settings
PaiTiCuoTiBenTests/
```

Images live under Documents `children/<id>/jobs/...` and `children/<id>/wrong/...`. SwiftData uses a local store with CloudKit turned off.
