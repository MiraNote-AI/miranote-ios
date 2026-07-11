# Edit Verb Widening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Natural edit phrasings ("change the sticker to blue", "贴纸改成蓝色", "change the photo ...") route to the sticker/photo word edits instead of falling through to chat.

**Architecture:** One shared `hasEditVerb` helper in MiraIntent+Image.swift consumed by `stickerEditIntent` and `photoIntent`'s freeEdit. Nothing downstream changes.

**Tech Stack:** Swift, XCTest, swiftlint. Spec: docs/specs/2026-07-10-edit-verb-widening-design.md. Refs #23. Ships inside PR #22 (branch feat/sticker-edit).

## Global Constraints

- Org Rule 3: Chinese cues in Swift source as unicode escapes.
- swiftlint --strict 0; suites only on shadow sim 35B7DA99-2D8B-4E9D-9848-FE17661F0B59.
- Verb list exactly as in the spec: EN "make ", "change ", "turn ", "edit ", "redraw ", "restyle ", "recolor ", "repaint ", "give ", "add ", "put "; ZH 把 改 换 变 给.

---

### Task 1: Shared edit-verb helper + widened cues

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerIntentTests.swift`, `MiraNoteKit/Tests/MiraNoteKitTests/MiraImageIntentTests.swift`

**Interfaces:**
- Consumes: existing `stickerEditIntent`, `photoIntent`.
- Produces: `static func hasEditVerb(_ lowered: String) -> Bool` (internal to MiraIntent).

- [ ] **Step 1: Write the failing tests**

Append to `MiraStickerIntentTests`:

```swift
    func testChangeVerbEditsTheSticker() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("change the sticker to blue", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testTurnTheStickerIntoADragonEdits() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("turn the sticker into a dragon", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testAddAHatToTheStickerEdits() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("add a hat to the sticker", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testChineseGaiWithoutBaEdits() {
        let editor = editorWithStickers(1)
        // "tie zhi gai cheng lan se" -- sticker, change to blue (no ba).
        let intent = MiraIntent.classify(
            "\u{8D34}\u{7EB8}\u{6539}\u{6210}\u{84DD}\u{8272}", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testChineseGeiAccessoryEdits() {
        let editor = editorWithStickers(1)
        // "gei tie zhi jia ding mao zi" -- give the sticker a hat.
        let intent = MiraIntent.classify(
            "\u{7ED9}\u{8D34}\u{7EB8}\u{52A0}\u{9876}\u{5E3D}\u{5B50}", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testAddAStickerOfACatStaysConverse() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("add a sticker of a cat", editor: editor)
        guard case .converse = intent else {
            return XCTFail("expected converse, got \(intent)")
        }
    }
```

Append to `MiraImageIntentTests`:

```swift
    func testChangeThePhotoIsAFreeEdit() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("change the photo to feel like winter", editor: editor)
        guard case .editPhoto(_, _, let instruction) = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
        XCTAssertTrue(instruction.contains("winter"))
    }
```

- [ ] **Step 2: Run to verify the new ones fail**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter "MiraStickerIntentTests|MiraImageIntentTests" 2>&1 | tail -4`
Expected: the 6 sticker additions and the photo addition FAIL (converse instead of edit); testAddAStickerOfACatStaysConverse may pass already (indefinite guard).

- [ ] **Step 3: Implement the helper and wire both call sites**

In `MiraIntent+Image.swift`, add near `stickerEditIntent`:

```swift
    /// The words that make an ask an EDIT -- shared by the sticker and
    /// photo free-edit families. Escaped cues: ba, gai, huan, bian, gei.
    static func hasEditVerb(_ lowered: String) -> Bool {
        let verbs = ["make ", "change ", "turn ", "edit ", "redraw ",
                     "restyle ", "recolor ", "repaint ", "give ", "add ", "put ",
                     "\u{628A}", "\u{6539}", "\u{6362}", "\u{53D8}", "\u{7ED9}"]
        return verbs.contains(where: lowered.contains)
    }
```

In `stickerEditIntent`, replace

```swift
        let editVerb = lowered.contains("make ") || lowered.contains("\u{628A}")
```

with

```swift
        let editVerb = Self.hasEditVerb(lowered)
```

In `photoIntent`, replace

```swift
        let freeEdit = mentionsPhoto
            && (lowered.contains("make ") || lowered.contains("\u{628A}"))
```

with

```swift
        let freeEdit = mentionsPhoto && Self.hasEditVerb(lowered)
```

- [ ] **Step 4: Run the full Kit suite**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | grep -E "Executed.*failures" | tail -1`
Expected: 171+ tests, 0 failures (all #21/#22 boundary tests double as regressions).

- [ ] **Step 5: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerIntentTests.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraImageIntentTests.swift \
        docs/specs/2026-07-10-edit-verb-widening-design.md \
        docs/plans/2026-07-10-edit-verb-widening.md
git commit -m "feat: widen the edit verbs both families understand

Refs #23

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Gates and PR update

- [ ] **Step 1: Lint from the repo root**

Run: `cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 2: Full app suites on the shadow simulator**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  2>&1 | grep -E "TEST" | tail -2
```
Expected: TEST SUCCEEDED.

- [ ] **Step 3: Push and update PR #22**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git push
gh pr comment 22 --repo MiraNote-AI/miranote-ios --body "Added #23 (same family, unmerged base): one shared edit-verb list so natural phrasings (change/turn/add/gai/huan/bian/gei ...) reach the sticker and photo edits instead of falling to chat. Spec: docs/specs/2026-07-10-edit-verb-widening-design.md. Kit suite and lint green; no pipeline changes."
```
Then edit the PR body to add `Closes #23` next to `Closes #21` (gh pr edit 22 --body-file with the updated text). Watch CI to green.

## Iterations

(Ledger: one line per act+verify cycle.)
