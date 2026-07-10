# Mira Image and Style Intents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mira ask bar can do everything the editor's image and style
buttons can: generate pictures/stickers (two candidates, tap to place),
restyle or cut out a photo with words, apply filters/frames, and change
text size/color.

**Architecture:** Extend the existing local cue router (`MiraIntent`) and
turn machinery (`MiraCanvasCoordinator`) -- no backend changes, no new
chrome except a two-thumbnail choice row on the Mira card. Slow work
(generate/stylize/cutout) runs the normal working-verb turn against the
`ImageStudioService`; instant work (filter/frame/size/color) mutates in
one undo snapshot and shows the receipt straight away.

**Tech Stack:** Swift / SwiftUI, MiraNoteKit package tests (XCTest),
XCUITest with `-UITEST` mocks. Spec:
`docs/specs/2026-07-10-mira-image-intents-design.md`.

## Global Constraints

- swiftlint --strict caps: 400-line file, 250-line type body, 50-line
  function. MiraCanvasCoordinator is at 365 lines: ALL new coordinator
  code goes in a new `MiraCanvasCoordinator+Images.swift`.
- Org Rule 3: no CJK in committed source; Chinese cues are unicode
  escapes (`"\u{753B}"`). Test files and docs are exempt but stay
  escape-style for consistency.
- Chinese cue escapes used below: draw `\u{753B}` (hua), generate
  `\u{751F}\u{6210}`, "give me a" `\u{6765}\u{4E00}\u{5F20}`, sticker
  `\u{8D34}\u{7EB8}`, photo `\u{7167}\u{7247}`, cut into
  `\u{62A0}\u{6210}`, black-white `\u{9ED1}\u{767D}`, polaroid
  `\u{62CD}\u{7ACB}\u{5F97}`, white frame `\u{767D}\u{6846}`, bigger
  `\u{5927}\u{4E00}\u{70B9}`, smaller `\u{5C0F}\u{4E00}\u{70B9}`,
  green `\u{7EFF}`, grey `\u{7070}`.
- Every commit: lint clean, Kit tests green. Verification and commits
  never share one command chain; explicit `cd` starts every commit.
- PR reference: Closes the issue filed in Task 0 (Rule 6).

---

### Task 0: File the tracking issue

- [ ] **Step 1: Create the issue**

```bash
gh issue create --repo MiraNote-AI/miranote-ios \
  --title "Let Mira trigger the image and style features the buttons have" \
  --label enhancement \
  --body "$(cat <<'EOF'
## Problem
AI features behind UI buttons (generate image/sticker, photo stylize and
cutout, filters/frames, text size/color) cannot be asked of the Mira
agent in words.

## Context
Spec: docs/specs/2026-07-10-mira-image-intents-design.md (approved
2026-07-10). Text transforms already route through Mira intents.

## Acceptance criteria
- [ ] "draw a paper crane" yields two candidates on the Mira card; tapping one places it (sticker asks also join MY STICKERS)
- [ ] "make the photo black and white" applies the filter instantly with a receipt; free-form photo asks restyle in place
- [ ] "turn the photo into a sticker" replaces it in place
- [ ] "make the title bigger" / "make the words green" work; Revert undoes any of the above in one step
- [ ] Ambiguous photo target yields a clarify card, canvas untouched
EOF
)"
```

Note the issue number; the plan calls it `#N` below.

---

### Task 1: Intent grammar (Kit) -- cases, targetPhoto, cues

**Files:**
- Create: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift`
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift`
  (add enum cases; insert one router call at the TOP of `classify`,
  before the polish/warmer cue block, so "make the photo warmer" wins
  the filter, not the polish)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraImageIntentTests.swift`

**Interfaces:**
- Consumes: `CanvasViewModel.orderedItems/selectedItemID/item(_:)`,
  `ImageRef.fileName`, `ImageFileStore.data(forFileName:)`.
- Produces (later tasks rely on these exact shapes):

```swift
// New MiraIntent cases (in MiraIntent.swift's enum):
case generateImage(prompt: String, sticker: Bool)
case editPhoto(CanvasItem.ID, imageData: Data, instruction: String)
case makeSticker(CanvasItem.ID, imageData: Data, prompt: String)
case applyFilter(CanvasItem.ID, name: String)   // "" clears
case applyFrame(CanvasItem.ID, name: String)    // "" clears
case resizeText(CanvasItem.ID, up: Bool)
case recolorText(CanvasItem.ID, colorName: String)
case clarifyPhoto                                // ambiguous target

// MiraIntent+Image.swift:
static func classifyImageOrStyle(
    _ lowered: String, prompt: String,
    editor: CanvasViewModel, imageStore: ImageFileStore
) -> MiraIntent?              // nil = not ours, continue the old router
static func targetPhoto(editor: CanvasViewModel) -> (CanvasItem.ID, ImageRef)??
    // .some(match): unambiguous; .some(nil) impossible; nil when zero
    // photos -- use a small enum instead:
enum PhotoTarget { case one(CanvasItem.ID, ImageRef); case none; case ambiguous }
static func photoTarget(editor: CanvasViewModel) -> PhotoTarget
```

- [ ] **Step 1: Write the failing classification tests**

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraImageIntentTests: XCTestCase {
    private func editorWithPhotos(_ count: Int, selectFirst: Bool = false) -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        var first: CanvasItem.ID?
        for index in 0..<count {
            let ids = editor.addImages(
                [ImageRef(displayName: "photo \(index)", fileName: "f\(index).png")],
                around: CGPoint(x: 150, y: 100 + CGFloat(index) * 200)
            )
            if index == 0 { first = ids.first }
        }
        if selectFirst, let first { editor.select(first) }
        return editor
    }

    func testDrawClassifiesAsGeneration() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("draw a paper crane", editor: editor)
        guard case .generateImage(let prompt, let sticker) = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("paper crane"))
        XCTAssertFalse(sticker)
    }

    func testStickerCueGeneratesStickerKind() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify(
            "\u{6765}\u{4E00}\u{5F20}\u{5496}\u{5561}\u{676F}\u{8D34}\u{7EB8}",
            editor: editor
        )
        guard case .generateImage(_, let sticker) = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
        XCTAssertTrue(sticker)
    }

    func testPhotoWarmerIsTheFilterNotPolish() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("make the photo warmer", editor: editor)
        guard case .applyFilter(_, let name) = intent else {
            return XCTFail("expected applyFilter, got \(intent)")
        }
        XCTAssertEqual(name, "warm")
    }

    func testAmbiguousPhotoAsksToTap() {
        let editor = editorWithPhotos(2)
        let intent = MiraIntent.classify("make the photo black and white", editor: editor)
        guard case .clarifyPhoto = intent else {
            return XCTFail("expected clarifyPhoto, got \(intent)")
        }
    }

    func testSelectedPhotoWinsWhenSeveral() {
        let editor = editorWithPhotos(2, selectFirst: true)
        let intent = MiraIntent.classify(
            "\u{628A}\u{7167}\u{7247}\u{9ED1}\u{767D}", editor: editor
        )
        guard case .applyFilter = intent else {
            return XCTFail("expected applyFilter, got \(intent)")
        }
    }

    func testBiggerTargetsTheTextBlock() {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("hello words", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify("make it bigger", editor: editor)
        guard case .resizeText(let target, let up) = intent else {
            return XCTFail("expected resizeText, got \(intent)")
        }
        XCTAssertEqual(target, id)
        XCTAssertTrue(up)
    }

    func testGreenRecolorsToForest() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText("hello words", at: CGPoint(x: 150, y: 80))
        let intent = MiraIntent.classify(
            "\u{6362}\u{6210}\u{7EFF}\u{8272}", editor: editor
        )
        guard case .recolorText(_, let color) = intent else {
            return XCTFail("expected recolorText, got \(intent)")
        }
        XCTAssertEqual(color, "forest")
    }

    func testStickerCutoutOnThePhoto() {
        let editor = editorWithPhotos(1)
        let intent = MiraIntent.classify("turn the photo into a sticker", editor: editor)
        guard case .makeSticker = intent else {
            return XCTFail("expected makeSticker, got \(intent)")
        }
    }
}
```

Note: `editPhoto`/`makeSticker` carry `imageData` captured at classify
time; the tests above use fileNames with no stored bytes, so classify
must tolerate missing data by carrying `Data()` (the coordinator's
perform step will fail the turn with the calm card if bytes are empty
AND the op needs them -- covered in Task 2 tests).

- [ ] **Step 2: Run to verify failures**

Run: `swift test --package-path MiraNoteKit --filter MiraImageIntentTests`
Expected: compile errors (cases missing) -> add EMPTY case stubs +
`classifyImageOrStyle` returning nil, re-run, expected: assertion FAILs.

- [ ] **Step 3: Implement the router**

`MiraIntent+Image.swift` (complete):

```swift
import Foundation

// The image and style families of the Mira cue router (split from
// MiraIntent.swift for the 400-line file cap). Checked BEFORE the text
// transform cues so photo-flavored wording ("make the photo warmer")
// never falls into polish.
extension MiraIntent {
    enum PhotoTarget {
        case one(CanvasItem.ID, ImageRef)
        case none
        case ambiguous
    }

    @MainActor
    static func photoTarget(editor: CanvasViewModel) -> PhotoTarget {
        let photos = editor.orderedItems.compactMap { item -> (CanvasItem.ID, ImageRef)? in
            guard case .image(let ref) = item.content else { return nil }
            return (item.id, ref)
        }
        if let selected = editor.selectedItemID,
           let match = photos.first(where: { $0.0 == selected }) {
            return .one(match.0, match.1)
        }
        if photos.count == 1, let only = photos.first {
            return .one(only.0, only.1)
        }
        return photos.isEmpty ? .none : .ambiguous
    }

    /// nil = no image/style cue matched; the caller continues the text router.
    @MainActor
    static func classifyImageOrStyle(
        _ lowered: String,
        prompt: String,
        editor: CanvasViewModel,
        imageStore: ImageFileStore
    ) -> MiraIntent? {
        if let generation = generationIntent(lowered, prompt: prompt) {
            return generation
        }
        let mentionsPhoto = ["photo", "picture", "\u{7167}\u{7247}", "\u{56FE}"]
            .contains(where: lowered.contains)

        if let photoIntent = photoIntent(
            lowered, prompt: prompt, mentionsPhoto: mentionsPhoto,
            editor: editor, imageStore: imageStore
        ) {
            return photoIntent
        }
        return styleIntent(lowered, editor: editor)
    }

    @MainActor
    private static func generationIntent(_ lowered: String, prompt: String) -> MiraIntent? {
        let cues = ["draw ", "paint ", "generate ", "\u{753B}",
                    "\u{751F}\u{6210}", "\u{6765}\u{4E00}\u{5F20}"]
        guard cues.contains(where: lowered.contains) else { return nil }
        let sticker = lowered.contains("sticker") || lowered.contains("\u{8D34}\u{7EB8}")
        return .generateImage(prompt: prompt, sticker: sticker)
    }

    @MainActor
    private static func photoIntent(
        _ lowered: String, prompt: String, mentionsPhoto: Bool,
        editor: CanvasViewModel, imageStore: ImageFileStore
    ) -> MiraIntent? {
        let stickerCut = lowered.contains("into a sticker")
            || lowered.contains("\u{62A0}\u{6210}")
        let filterName = filterCue(lowered)
        let frameName = frameCue(lowered)
        let freeEdit = mentionsPhoto && lowered.contains("make ")
        guard stickerCut || filterName != nil || frameName != nil || freeEdit else {
            return nil
        }
        // All photo families need one unambiguous target.
        switch photoTarget(editor: editor) {
        case .none:
            return stickerCut || filterName != nil || frameName != nil || mentionsPhoto
                ? .clarifyPhoto : nil
        case .ambiguous:
            return .clarifyPhoto
        case .one(let id, let ref):
            let data = imageStore.data(forFileName: ref.fileName) ?? Data()
            if stickerCut {
                return .makeSticker(id, imageData: data, prompt: ref.displayName)
            }
            if let filterName {
                return .applyFilter(id, name: filterName)
            }
            if let frameName {
                return .applyFrame(id, name: frameName)
            }
            return .editPhoto(id, imageData: data, instruction: prompt)
        }
    }

    private static func filterCue(_ lowered: String) -> String? {
        if lowered.contains("black and white") || lowered.contains("b&w")
            || lowered.contains("\u{9ED1}\u{767D}") { return "bw" }
        if lowered.contains("warmer") || lowered.contains("warm filter")
            || lowered.contains("warm look") { return "warm" }
        if lowered.contains("film look") || lowered.contains("film filter") { return "film" }
        if lowered.contains("match the page") { return "match" }
        if lowered.contains("no filter") || lowered.contains("original look") { return "" }
        return nil
    }

    private static func frameCue(_ lowered: String) -> String? {
        if lowered.contains("polaroid") || lowered.contains("\u{62CD}\u{7ACB}\u{5F97}") {
            return "polaroid"
        }
        if lowered.contains("white frame") || lowered.contains("\u{767D}\u{6846}") {
            return "white"
        }
        if lowered.contains("no frame") { return "" }
        return nil
    }

    @MainActor
    private static func styleIntent(_ lowered: String, editor: CanvasViewModel) -> MiraIntent? {
        let up = ["bigger", "larger", "\u{5927}\u{4E00}\u{70B9}", "\u{653E}\u{5927}"]
            .contains(where: lowered.contains)
        let down = ["smaller", "\u{5C0F}\u{4E00}\u{70B9}", "\u{7F29}\u{5C0F}"]
            .contains(where: lowered.contains)
        let color = colorCue(lowered)
        guard up || down || color != nil else { return nil }
        guard let (id, _) = targetTextBlock(editor: editor) else { return nil }
        if up || down { return .resizeText(id, up: up) }
        return .recolorText(id, colorName: color!)
    }

    private static func colorCue(_ lowered: String) -> String? {
        if lowered.contains("green") || lowered.contains("forest")
            || lowered.contains("\u{7EFF}") { return "forest" }
        if lowered.contains("grey") || lowered.contains("gray")
            || lowered.contains("\u{7070}") { return "textSecondary" }
        if lowered.contains("black") || lowered.contains("ink")
            || lowered.contains("\u{9ED1}\u{8272}") { return "ink" }
        if lowered.contains("brown") || lowered.contains("taupe")
            || lowered.contains("\u{68D5}") { return "taupe" }
        if lowered.contains("tan") || lowered.contains("beige") { return "tan" }
        return nil
    }
}
```

In `MiraIntent.swift`:
1. Add the eight cases to the enum.
2. Extract the existing selected-else-longest text lookup into
   `static func targetTextBlock(editor:) -> (CanvasItem.ID, String)?`
   (it is today the local `targetText()` closure inside classify; hoist
   it unchanged so `MiraIntent+Image.swift` can call it).
3. At the top of `classify`, before the polish block:

```swift
if let imageIntent = classifyImageOrStyle(
    lowered, prompt: prompt, editor: editor, imageStore: classifyImageStore
) {
    return imageIntent
}
```

with `nonisolated(unsafe) static var classifyImageStore = ImageFileStore()`
(overridable in tests; simple POC-grade injection consistent with the
static classifier).

4. Extend `var verb: String` with: generateImage -> "Painting...",
   editPhoto -> "Restyling the photo...", makeSticker ->
   "Cutting the sticker...", instant cases -> "Working..." (never
   shown; they settle before the 400 ms delay), clarifyPhoto reuses the
   clarify verb. Extend `affectedItems` to include the target id for
   editPhoto/makeSticker/applyFilter/applyFrame/resizeText/recolorText.
5. `perform(...)`: for now make the new cases `throw`
   `MiraUnhandledError()` placeholder-free by routing clarifyPhoto like
   clarifyNoText (a MiraClarifyError with "More than one photo here --
   tap the one you mean and ask again." and chips []), and the six real
   cases `fatalError` is FORBIDDEN -- instead have them throw a plain
   `MiraTimeoutError` stand-in? NO: Task 2 lands `perform` properly;
   to keep THIS task green without dead code, implement `perform` for
   the instant + slow cases in Task 2 and in THIS task only add the
   cases plus classification. Swift exhaustiveness forces SOME body:
   return `.reply("(image intents land in the next commit)", nil)` --
   a compiling, honest interim that Task 2 deletes. Tests in this task
   only exercise `classify`, so the interim body is never user-visible
   (the two tasks ship in one PR).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path MiraNoteKit --filter MiraImageIntentTests`
Expected: PASS (8 tests). Also run the full Kit suite:
`swift test --package-path MiraNoteKit` -- all green.

- [ ] **Step 5: Lint + commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict --quiet && \
git add MiraNoteKit && git commit -m "feat(kit): teach the Mira router the image and style cue families

Refs #N

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Coordinator plumbing -- services, slow turns, instant settles

**Files:**
- Create: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift`
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator.swift`
  (init params; run() timeout pick; settle() delegating new outcomes),
  `MiraIntent.swift` (real `perform` for the new cases -- delete the
  Task 1 interim)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraImageTurnTests.swift`

**Interfaces:**
- Consumes: Task 1 cases; `ImageStudioService` (generate/stylize/
  cutout/outline); `CanvasViewModel.setImageFilter/setImageFrame/
  setTextPointSize/setTextColorName/replaceImageFile/
  replaceImageWithSticker/beginChange`; `ScriptedImageStudio` test
  double (new, in the test file).
- Produces:

```swift
// MiraOutcome additions:
case imageChoices([Data], prompt: String, sticker: Bool)
case imageReplaced(CanvasItem.ID, Data, MiraReceipt)          // stylize
case stickerReplaced(CanvasItem.ID, Data, prompt: String, MiraReceipt)
case filterApplied(CanvasItem.ID, name: String, MiraReceipt)
case frameApplied(CanvasItem.ID, name: String, MiraReceipt)
case textResized(CanvasItem.ID, up: Bool, MiraReceipt)
case textRecolored(CanvasItem.ID, colorName: String, MiraReceipt)

// Coordinator init gains (defaults keep every existing call site):
imageStudio: ImageStudioService = MockImageStudioService(),
imageTimeout: Duration = .seconds(150),
imageStore: ImageFileStore = ImageFileStore(),
stickerFavorites: StickerFavoritesStore = StickerFavoritesStore()

// Phase addition:
case imageChoices([Data], prompt: String, sticker: Bool)
```

- [ ] **Step 1: Write the failing turn tests**

```swift
import XCTest
@testable import MiraNoteKit

/// Image studio double with instant, distinguishable outputs.
struct ScriptedImageStudio: ImageStudioService {
    var generated: [Data] = [Data("img-A".utf8), Data("img-B".utf8)]
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { generated }
    func cutout(image: Data, target: String?) async throws -> Data { Data("cut".utf8) }
    func stylize(image: Data, instruction: String) async throws -> Data { Data("styled".utf8) }
    func outline(image: Data) async throws -> Data { Data("outlined".utf8) }
    func describe(image: Data) async throws -> String { "a scripted look" }
}

@MainActor
final class MiraImageTurnTests: XCTestCase {
    private func makeCoordinator(tempDir: URL) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(),
            chat: ScriptedChat(),
            workingDelay: .milliseconds(1),
            timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: ScriptedImageStudio(),
            imageTimeout: .seconds(5),
            imageStore: ImageFileStore(directory: tempDir),
            stickerFavorites: StickerFavoritesStore(
                url: tempDir.appendingPathComponent("favs.json"))
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-image-\(UUID().uuidString)")
    }

    func testGenerateAskYieldsTwoChoices() async {
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("draw a paper crane", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(let images, _, let sticker) = coordinator.phase else {
            return XCTFail("expected imageChoices, got \(coordinator.phase)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertFalse(sticker)
        XCTAssertTrue(editor.items.isEmpty, "nothing lands until a tap")
    }

    func testInstantFilterAppliesWithOneUndo() async {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "p", fileName: "p.png")],
                                  around: CGPoint(x: 150, y: 100)).first!
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make the photo black and white", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .image(let ref) = editor.item(id)!.content else { return XCTFail() }
        XCTAssertEqual(ref.filterName, "bw")
        editor.undo()
        guard case .image(let restored) = editor.item(id)!.content else { return XCTFail() }
        XCTAssertEqual(restored.filterName, "", "one undo restores")
    }

    func testStylizeReplacesPixelsInPlace() async {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let fileName = try! store.save(Data("orig".utf8), id: UUID())
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addImages([ImageRef(displayName: "p", fileName: fileName)],
                                  around: CGPoint(x: 150, y: 100)).first!
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("make the photo feel like autumn", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .image(let ref) = editor.item(id)!.content else { return XCTFail() }
        XCTAssertEqual(store.data(forFileName: ref.fileName), Data("styled".utf8))
    }

    func testResizeTextStepsUpAndRecolors() async {
        let editor = CanvasViewModel(memory: Memory())
        let id = editor.addText("hello words", at: CGPoint(x: 150, y: 80), pointSize: 17)
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make it bigger", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .text(let block) = editor.item(id)!.content else { return XCTFail() }
        XCTAssertEqual(block.pointSize, 30, "17 steps up to 30")

        coordinator.dismiss()
        coordinator.ask("make it green", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .text(let recolored) = editor.item(id)!.content else { return XCTFail() }
        XCTAssertEqual(recolored.colorName, "forest")
    }
}
```

(If `TextBlock` stores its color under a different property than
`colorName`, use the actual property -- check `setTextColorName` in
`CanvasViewModel.swift:` its written field is the source of truth.)

- [ ] **Step 2: Run to verify failures**

Run: `swift test --package-path MiraNoteKit --filter MiraImageTurnTests`
Expected: compile errors (init params, outcomes, phase missing), then
FAILs once stubs exist.

- [ ] **Step 3: Implement**

In `MiraCanvasCoordinator.swift` (small diffs only):
- Add the four init params + stored lets (`imageStudio`,
  `imageTimeout`, `imageStore`, `stickerFavorites`).
- In `run()`, pick the deadline:
  `let limit = intent.isSlowImageWork ? imageTimeout : timeout` and pass
  `[imageStudio]` into the perform closure:
  `try await intent.perform(text: text, chat: chat, sessionID: sessionID, imageStudio: imageStudio)`.
- In `settle()`, add ONE line per new outcome delegating to the
  extension: `case .filterApplied(let id, let name, let receipt):
  settleFilter(id, name: name, receipt: receipt, editor: editor)` etc.,
  and `case .imageChoices(let images, let prompt, let sticker):
  phase = .imageChoices(images, prompt: prompt, sticker: sticker)`.
- Pass `imageStore` into classify:
  `MiraIntent.classifyImageStore = imageStore` in init (test injection
  point stays the static; the coordinator keeps it fresh).

In `MiraCanvasCoordinator+Images.swift` (complete):

```swift
import Foundation

// Image and style outcome application + the two-candidate flow (split
// from MiraCanvasCoordinator.swift for the 400-line file cap).
extension MiraCanvasCoordinator {
    var isShowingImageChoices: Bool {
        if case .imageChoices = phase { return true }
        return false
    }

    /// Tap on candidate `index`: write the file, land it, receipt.
    public func placeImageChoice(_ index: Int, editor: CanvasViewModel) {
        guard case .imageChoices(let images, let prompt, let sticker) = phase,
              images.indices.contains(index),
              let fileName = try? imageStore.save(images[index], id: UUID())
        else { return }
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 90, 4000))
        if sticker {
            let generated = GeneratedSticker(
                prompt: prompt, symbolName: "sparkles", fileName: fileName)
            editor.addSticker(generated, at: position)
            stickerFavorites.add(generated)
            showReceipt(MiraReceipt(
                changed: "Added a sticker.",
                kept: "Everything else is untouched."), editor: editor)
        } else {
            editor.addImages([ImageRef(displayName: prompt, fileName: fileName)],
                             around: position)
            showReceipt(MiraReceipt(
                changed: "Added a picture.",
                kept: "Everything else is untouched."), editor: editor)
        }
    }

    /// The xmark: both candidates evaporate, canvas untouched.
    public func discardImageChoices() {
        guard case .imageChoices = phase else { return }
        phase = .idle
    }

    func settleImageReplaced(_ id: CanvasItem.ID, data: Data,
                             receipt: MiraReceipt, editor: CanvasViewModel) {
        guard editor.item(id) != nil,
              let fileName = try? imageStore.save(data, id: UUID()) else {
            phase = .failure(MiraFailure(
                kind: .retry,
                message: "The photo I was working on is gone, so I left everything as is.",
                chips: ["Try again"]))
            return
        }
        editor.replaceImageFile(itemID: id, fileName: fileName)
        showReceipt(receipt, editor: editor)
    }

    func settleStickerReplaced(_ id: CanvasItem.ID, data: Data, prompt: String,
                               receipt: MiraReceipt, editor: CanvasViewModel) {
        guard editor.item(id) != nil,
              let fileName = try? imageStore.save(data, id: UUID()) else {
            phase = .failure(MiraFailure(
                kind: .retry,
                message: "The photo I was working on is gone, so I left everything as is.",
                chips: ["Try again"]))
            return
        }
        let sticker = GeneratedSticker(prompt: prompt, symbolName: "sparkles",
                                       fileName: fileName)
        editor.replaceImageWithSticker(itemID: id, sticker: sticker)
        stickerFavorites.add(sticker)
        showReceipt(receipt, editor: editor)
    }

    func settleFilter(_ id: CanvasItem.ID, name: String,
                      receipt: MiraReceipt, editor: CanvasViewModel) {
        editor.beginChange()
        editor.setImageFilter(itemID: id, to: name)
        showReceipt(receipt, editor: editor)
    }

    func settleFrame(_ id: CanvasItem.ID, name: String,
                     receipt: MiraReceipt, editor: CanvasViewModel) {
        editor.beginChange()
        editor.setImageFrame(itemID: id, to: name)
        showReceipt(receipt, editor: editor)
    }

    func settleTextResize(_ id: CanvasItem.ID, up: Bool,
                          receipt: MiraReceipt, editor: CanvasViewModel) {
        guard case .text(let block) = editor.item(id)?.content else { return }
        let steps: [CGFloat] = [13, 17, 30]
        let current = steps.min { abs($0 - block.pointSize) < abs($1 - block.pointSize) } ?? 17
        let index = steps.firstIndex(of: current) ?? 1
        let next = steps[max(0, min(steps.count - 1, index + (up ? 1 : -1)))]
        editor.beginChange()
        editor.setTextPointSize(itemID: id, to: next)
        showReceipt(receipt, editor: editor)
    }

    func settleTextRecolor(_ id: CanvasItem.ID, colorName: String,
                           receipt: MiraReceipt, editor: CanvasViewModel) {
        editor.beginChange()
        editor.setTextColorName(itemID: id, to: colorName)
        showReceipt(receipt, editor: editor)
    }
}
```

In `MiraIntent.swift`'s `perform` (replace the Task 1 interim; the
signature gains `imageStudio: ImageStudioService`):

```swift
case .generateImage(let prompt, let sticker):
    let images = try await imageStudio.generate(
        kind: sticker ? .sticker : .background, prompt: prompt)
    guard !images.isEmpty else { throw MiraTimeoutError() }
    return .imageChoices(Array(images.prefix(2)), prompt: prompt, sticker: sticker)
case .editPhoto(let id, let data, let instruction):
    guard !data.isEmpty else { throw MiraTimeoutError() }
    let styled = try await imageStudio.stylize(image: data, instruction: instruction)
    return .imageReplaced(id, styled, MiraReceipt(
        changed: "Restyled the photo.", kept: "Undo brings the old one back."))
case .makeSticker(let id, let data, let prompt):
    guard !data.isEmpty else { throw MiraTimeoutError() }
    let cut = try await imageStudio.cutout(image: data, target: nil)
    let outlined = try await imageStudio.outline(image: cut)
    return .stickerReplaced(id, outlined, prompt: prompt, MiraReceipt(
        changed: "Made it a sticker.", kept: "Undo brings the photo back."))
case .applyFilter(let id, let name):
    return .filterApplied(id, name: name, MiraReceipt(
        changed: name.isEmpty ? "Cleared the filter." : "Changed the photo's look.",
        kept: "Undo restores it."))
case .applyFrame(let id, let name):
    return .frameApplied(id, name: name, MiraReceipt(
        changed: name.isEmpty ? "Removed the frame." : "Framed the photo.",
        kept: "Undo restores it."))
case .resizeText(let id, let up):
    return .textResized(id, up: up, MiraReceipt(
        changed: up ? "Made the words bigger." : "Made the words smaller.",
        kept: "Undo restores them."))
case .recolorText(let id, let colorName):
    return .textRecolored(id, colorName: colorName, MiraReceipt(
        changed: "Recolored the words.", kept: "Undo restores them."))
case .clarifyPhoto:
    throw MiraClarifyError(
        question: "More than one photo here -- tap the one you mean and ask again.",
        chips: [])
```

plus `var isSlowImageWork: Bool` (generateImage/editPhoto/makeSticker).
Update the OTHER perform call sites' signatures (grep
`perform(text:` -- run() is the only caller).

- [ ] **Step 4: Run tests**

`swift test --package-path MiraNoteKit` -- all green including the new
turn tests and every pre-existing suite (the init defaults keep
MiraPageIntentTests compiling untouched).

- [ ] **Step 5: Lint + commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict --quiet && \
git add MiraNoteKit && git commit -m "feat(kit): run image and style asks through the Mira turn machinery

Refs #N

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Choice placement tests (Kit)

**Files:**
- Test: append to `MiraNoteKit/Tests/MiraNoteKitTests/MiraImageTurnTests.swift`

**Interfaces:** consumes Task 2's `placeImageChoice/discardImageChoices`.

- [ ] **Step 1: Write the failing tests**

```swift
func testPlacingAChoiceLandsAndReceipts() async {
    let dir = tempDir
    let editor = CanvasViewModel(memory: Memory())
    let coordinator = makeCoordinator(tempDir: dir)
    coordinator.ask("draw a paper crane", editor: editor)
    await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }

    coordinator.placeImageChoice(1, editor: editor)
    guard case .receipt(let receipt) = coordinator.phase else {
        return XCTFail("expected receipt, got \(coordinator.phase)")
    }
    XCTAssertEqual(receipt.changed, "Added a picture.")
    XCTAssertEqual(editor.items.count, 1)
    guard case .image(let ref) = editor.items[0].content else { return XCTFail() }
    XCTAssertEqual(ImageFileStore(directory: dir).data(forFileName: ref.fileName),
                   Data("img-B".utf8), "the tapped candidate landed")
}

func testStickerChoiceJoinsFavorites() async {
    let dir = tempDir
    let favorites = StickerFavoritesStore(url: dir.appendingPathComponent("favs.json"))
    let editor = CanvasViewModel(memory:Emory())
    let coordinator = makeCoordinator(tempDir: dir)
    coordinator.ask("make a sticker of a coffee cup", editor: editor)
    await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
    coordinator.placeImageChoice(0, editor: editor)
    XCTAssertEqual(favorites.all().count, 1, "the placed sticker is reusable")
}

func testDiscardKeepsCanvasUntouched() async {
    let editor = CanvasViewModel(memory: Memory())
    let coordinator = makeCoordinator(tempDir: tempDir)
    coordinator.ask("draw a paper crane", editor: editor)
    await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
    coordinator.discardImageChoices()
    guard case .idle = coordinator.phase else { return XCTFail() }
    XCTAssertTrue(editor.items.isEmpty)
}
```

(`Emory` above is a deliberate reminder to type-check -- fix to `Memory`
when writing the real file; the plan's code is hand-written.)

- [ ] **Step 2-4: fail -> already implemented in Task 2 -> pass**

Run: `swift test --package-path MiraNoteKit --filter MiraImageTurnTests`
Expected: PASS without further implementation (Task 2 built the flow);
if placement misbehaves, fix in the extension file.

- [ ] **Step 5: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict --quiet && \
git add MiraNoteKit && git commit -m "test(kit): lock the two-candidate placement and discard flow

Refs #N

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: App wiring -- choice row UI + UITest locks

**Files:**
- Modify: `App/Sources/Screens/EditorFlowView.swift` (coordinator init
  gains `imageStudio: services.imageStudio` -- one line),
  `App/Sources/Screens/Editor/MiraStrip.swift` (render `.imageChoices`)
- Test: `App/UITests/MiraImageAskUITests.swift` (new file -- the
  existing UITest classes sit near the 250-line type cap)

**Interfaces:** consumes `coordinator.phase == .imageChoices`,
`placeImageChoice(_:editor:)`, `discardImageChoices()`.

- [ ] **Step 1: MiraCard renders the choices**

In `MiraStrip.swift`, alongside the existing phase branches (reply/
receipt/failure), add:

```swift
case .imageChoices(let images, _, _):
    HStack(spacing: 10) {
        ForEach(Array(images.enumerated()), id: \.offset) { index, data in
            Button {
                coordinator.placeImageChoice(index, editor: editor)
            } label: {
                thumb(for: data)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mira.imageChoice.\(index)")
        }
        Spacer()
        Button {
            coordinator.discardImageChoices()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mira.imageChoice.dismiss")
    }

// helper next to the card's other view builders:
@ViewBuilder private func thumb(for data: Data) -> some View {
    if let image = UIImage(data: data) {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    } else {
        RoundedRectangle(cornerRadius: 12)
            .fill(Palette.tan.opacity(0.4))
            .frame(width: 84, height: 84)
    }
}
```

Match the surrounding card container exactly as the reply branch does
(same padding/background). If MiraStrip crosses the 400-line cap, move
the choices row into a new `MiraImageChoicesRow.swift` view file.

- [ ] **Step 2: Write the UITests**

```swift
import XCTest

/// Mira image/style asks (deterministic -UITEST doubles: the mock
/// studio returns two instant candidates).
final class MiraImageAskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private func startMemory() {
        XCTAssertTrue(app.buttons["Start a memory"].waitForExistence(timeout: 8))
        app.buttons["Start a memory"].tap()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 5))
    }

    private func ask(_ words: String) {
        let input = app.textFields["mira.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(words)
        app.buttons["mira.go"].tap()
    }

    func testDrawYieldsChoicesAndTapPlaces() {
        startMemory()
        ask("draw a paper crane")

        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "two candidates arrive")
        XCTAssertTrue(app.buttons["mira.imageChoice.1"].exists)
        first.tap()

        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))
        let placed = app.descendants(matching: .any)
            .matching(identifier: "element.image").firstMatch
        XCTAssertTrue(placed.waitForExistence(timeout: 5), "the pick landed")
    }

    func testFilterAskIsInstantWithReceipt() {
        startMemory()
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        // Two sample photos land; select one so the target is unambiguous.
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 300)).tap() // deselect paper first
        photo.tap()

        ask("make the photo black and white")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))
    }

    func testAmbiguousPhotoAsksToTapOne() {
        startMemory()
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        // Both samples on canvas, nothing selected -> ambiguous.
        let photo = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 0)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 300)).tap()

        ask("make the photo black and white")
        XCTAssertTrue(
            app.staticTexts["More than one photo here -- tap the one you mean and ask again."]
                .waitForExistence(timeout: 8)
        )
    }
}
```

- [ ] **Step 3: Run the new UITests on the SHADOW simulator only**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && xcodegen generate && \
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  -only-testing:MiraNoteUITests/MiraImageAskUITests
```
Expected: 3/3 pass. (NEVER the user simulator 6E165F5B for suites.)

- [ ] **Step 4: Lint + commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict --quiet && \
git add App && git commit -m "feat(ios): show Mira's two picture candidates and wire the studio

Refs #N

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Gates -- full suites, live film-strip, install

- [ ] **Step 1: Full clean-state verification (shadow sim)**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict --quiet
swift test --package-path MiraNoteKit
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59'
```
Expected: 0 lint, Kit all green, full app+UI suites green.

- [ ] **Step 2: Live film-strip pass against :8002**

Throwaway probe (real app, live studio, shadow sim; deleted before
commit): ask "draw a tiny paper crane" -> film the working verb, the
two candidates (60-90 s real generation), tap-to-place, receipt; ask
"make the photo black and white" on one sample -> instant receipt.
Screenshot loop + frame review per the established probe grammar.

- [ ] **Step 3: Install to the user simulator, verify timestamp**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
APP="$HOME/Library/Developer/Xcode/DerivedData/MiraNote-dkuprfnxlknmjmfxgtrgsugxgwii/Build/Products/Debug-iphonesimulator/MiraNote.app"
stat -f 'binary built: %Sm' "$APP/MiraNote"
xcrun simctl install 6E165F5B-C411-40B4-A1A7-940E548D0D21 "$APP"
xcrun simctl launch 6E165F5B-C411-40B4-A1A7-940E548D0D21 ai.miranote.app
```

---

### Task 6: PR

- [ ] **Step 1: Push and open (base = main, never stacked)**

```bash
cd /Users/mengjia/MiraNote/miranote-ios && git push -u origin feat/mira-image-intents
gh pr create --repo MiraNote-AI/miranote-ios \
  --title "feat(ios): let Mira run the image and style features by words" \
  --body "<what/why/verify per repo convention; Closes #N; links the spec>"
```
Expected: `checks / checks` green; report to Meng for review/merge.

---

## Self-review notes (run after drafting, fixed inline)

- Spec coverage: generation/choices (T1,T2,T3,T4), photo edits (T1,T2),
  filters/frames (T1,T2,T4), text size/color (T1,T2), clarify (T1,T4),
  receipts+undo (T2,T3), describe-after-edit: NOT yet covered -> added
  to Task 2's settleImageReplaced/settleStickerReplaced? Decision: the
  re-describe hook lives app-side (CanvasScene describeInBackground);
  coordinator cannot reach it. COVERED instead by CanvasScene's existing
  changeCount observation? It re-describes only via the photo-edit
  panel path. Accepted gap for this PR: Mira-restyled photos keep the
  stale summary until the next page open (backfill covers it) -- noted
  in the PR body as a known follow-up.
- Type consistency: `MiraClarifyError(question:chips:)`,
  `MiraReceipt(changed:kept:)`, `MiraFailure(kind:message:chips:)` all
  match existing usage; `Emory` typo flagged in Task 3 on purpose.
- No placeholders remain; every step carries code or exact commands.
