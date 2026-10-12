# 拍题错题本 · iOS 一期骨架

Phase-1 on-device skeleton for the iOS app described in PRD v1.5. Homework photos, recognized text, system answers, and the wrong-book stay in the phone sandbox (SwiftData + files). There is no object storage, no Mode B answer-sheet flow, and no WeChat login.

## Open in Xcode

1. Use Xcode 15 or newer, with an iOS 17+ simulator.
2. Open `PaiTiCuoTiBen.xcodeproj`.
3. Select the `PaiTiCuoTiBen` scheme and an iPhone simulator.
4. Run. For a physical device, pick your development team in Signing & Capabilities. The simulator can run with local signing.
5. Run tests with Product → Test, or:

```bash
xcodebuild test -scheme PaiTiCuoTiBen -destination 'platform=iOS Simulator,name=iPhone 16'
```

The first launch asks for a child profile (at most 5 active children). Import one or more pages, generate the local cards, then open the result and the wrong book.

## What this skeleton does

- Child profiles: create, edit, switch, archive, restore, delete. Switching children clears upload drafts that have not generated question cards yet.
- Mode A import: grade and subject are required, answer context is student handwriting or a self-mark hint, pages come from the photo library or the camera, and an optional teacher-key file (Word, image, or PDF) is copied into the sandbox.
- Review cards from a local mock parse: one high-confidence arithmetic card and one low-confidence open card per page.
- System grading. Confidence at or above the threshold (default 0.85, adjustable in Settings) can auto-lock an objective question. Below that, the card stays pending and is not written to the wrong book.
- Result page with two views: per-question breakdown, and a summary grouped by question type.
- Wrong book: confirmed wrong answers only, with the student snapshot, canonical text, at least one step, and error analysis (`pending` / `ready` / `failed`).
- Settings: privacy note, zip backup, 30-day original-page cleanup (wrong-book crops stay), and the usage note.

Verdict authority is only `user_confirm`, `auto_canonical`, or `auto_objective`. A teacher file is stored as `canonical_answer.source_refs`. Self-mark traces are a hint only.

## What is stubbed

| Piece | Current behavior |
| --- | --- |
| OCR and question cutting | `JobPipeline.mockParse` writes placeholder cards. It does not call Vision. |
| `POST /v1/inference/solve` | `StubInferenceClient` returns on-device text and steps. `1 + 1` is the high-confidence sample. |
| `POST /v1/inference/grade` | String compare on device. Empty answers stay pending. |
| `POST /v1/inference/error-analysis` | Fixed points and avoidance tips, clamped to 1–3 points. |
| `POST /v1/inference/summary-groups` | Groups the questions already stored on device. |
| Teacher key | The file is saved locally. Word / PDF text is not parsed, and it is not a grading authority. |
| Apple Sign-In | Not wired. Profiles are local. |
| Similar questions | Not in this phase. |

`InferenceClient` is the thin gateway. The stub never opens a network connection.

## Next milestones

1. **Vision OCR.** Replace the mock cards with on-device text recognition and question cropping. Low-confidence cuts stay on the review card.
2. **Real inference.** Add a remote `InferenceClient` for `/v1/inference/solve`, `/grade`, `/error-analysis`, and `/summary-groups`. Payloads are cropped text for that call only and are not stored on our servers.
3. **Word teacher key.** Parse `.docx` first, then images and PDF. Align the final answer with the teacher file when parsing works, and keep solution steps system-generated. Offer a retry with docx or an image when parsing fails.

## Layout

```
PaiTiCuoTiBen.xcodeproj
PaiTiCuoTiBen/
  Domain/          grading rules, enums
  Models/          Child, LocalJob, Page, Question, Answer, CanonicalAnswer, Verdict, WrongItem
  Persistence/     SwiftData, sandbox files, zip backup
  Inference/       InferenceClient + StubInferenceClient
  Services/        JobPipeline
  UI/              child switcher, import, review, dual result, wrong book, settings
PaiTiCuoTiBenTests/
```

Images live under Documents `children/<id>/jobs/...` and `children/<id>/wrong/...`. SwiftData uses a local store with CloudKit turned off.
