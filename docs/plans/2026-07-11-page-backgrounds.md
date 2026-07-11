# Page Backgrounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pages carry an optional AI-generated full-bleed background (Zhaoyan's :8002 background command) set and cleared through Mira, over a new mockup-style default gradient.

**Architecture:** `Memory.backgroundFileName` (decodeIfPresent-compatible) + one shared `PageBackdrop` view consumed by the editor paper and StaticPageView; the Mira router gains a background family checked before generation; the two-candidate picker generalizes from `sticker: Bool` to `ImageChoicePlacement` so a tapped background candidate lands via a new `setBackground` mutator.

**Tech Stack:** Swift/SwiftUI, XCTest, swiftlint. Spec: docs/specs/2026-07-11-page-backgrounds-design.md. Refs #24. Branch feat/page-backgrounds. Backend untouched.

## Global Constraints

- Org Rule 3: Chinese cues in Swift source as unicode escapes.
- swiftlint --strict 0 (file cap 400, type 250, function 50); suites ONLY on shadow sim 35B7DA99-2D8B-4E9D-9848-FE17661F0B59, never 6E165F5B-C411-40B4-A1A7-940E548D0D21.
- Mutators snapshot internally via beginChange(); never wrap them in another beginChange.
- Copy strings are exact: "Painting the backdrop...", "Set the page background.", "Cleared the background.", "Undo restores it.", "Everything else is untouched."
- Default gradient hexes exactly 0xF0B78E (top) and 0x702E4E (bottom).

---

### Task 1: Model -- Memory.backgroundFileName + setBackground mutator

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/Models.swift` (struct ~line 18-47, Codable extension ~line 57-86)
- Create: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel+Background.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MemoryBackgroundTests.swift` (create)

**Interfaces:**
- Produces: `Memory.backgroundFileName: String` (default ""), init param `backgroundFileName: String = ""` placed after `items`; `CanvasViewModel.setBackground(fileName: String)` (beginChange inside, one undo per call). Tasks 3-4 rely on both names exactly.

- [ ] **Step 1: Write the failing tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MemoryBackgroundTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MemoryBackgroundTests: XCTestCase {
    func testLegacySaveWithoutFieldDecodesToEmpty() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"old page",
         "body":"","createdAt":700000000,"memoryDate":700000000,"items":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let memory = try decoder.decode(Memory.self, from: Data(legacy.utf8))
        XCTAssertEqual(memory.backgroundFileName, "", "old saves mean no background")
    }

    func testBackgroundSurvivesARoundTrip() throws {
        var memory = Memory(title: "trip")
        memory.backgroundFileName = "bg.png"
        let data = try JSONEncoder().encode(memory)
        let back = try JSONDecoder().decode(Memory.self, from: data)
        XCTAssertEqual(back.backgroundFileName, "bg.png")
    }

    func testSetBackgroundIsOneUndo() {
        let editor = CanvasViewModel(memory: Memory())
        editor.setBackground(fileName: "bg.png")
        XCTAssertEqual(editor.memory.backgroundFileName, "bg.png")
        XCTAssertTrue(editor.canUndo)
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "", "one undo clears it back")
    }

    func testClearViaEmptyFileName() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        editor.setBackground(fileName: "")
        XCTAssertEqual(editor.memory.backgroundFileName, "")
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "bg.png")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MemoryBackgroundTests 2>&1 | tail -4`
Expected: compile FAILURE -- `backgroundFileName` is not a member of Memory.

- [ ] **Step 3: Add the field to Memory**

In `MiraNoteKit/Sources/MiraNoteKit/Models.swift`:

(a) After `public var items: [CanvasItem]` (line ~28):

```swift
    /// File name of the page's full-bleed background in the ImageFileStore;
    /// empty = the default gradient backdrop.
    public var backgroundFileName: String
```

(b) Init gains a defaulted parameter after `items` and assigns it:

```swift
    public init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        createdAt: Date = .now,
        memoryDate: Date? = nil,
        savedAt: Date? = nil,
        items: [CanvasItem] = [],
        backgroundFileName: String = ""
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.memoryDate = memoryDate ?? createdAt
        self.savedAt = savedAt
        self.items = items
        self.backgroundFileName = backgroundFileName
    }
```

(c) Codable extension: add `backgroundFileName` to `CodingKeys`; decode with
`decodeIfPresent ?? ""` (the established pattern); encode unconditionally:

```swift
    private enum CodingKeys: String, CodingKey {
        case id, title, body, createdAt, memoryDate, savedAt, items, backgroundFileName
    }
```

In `init(from:)`, add to the `self.init(...)` call after `items:`:

```swift
            items: try container.decodeIfPresent([CanvasItem].self, forKey: .items) ?? [],
            backgroundFileName: try container.decodeIfPresent(String.self, forKey: .backgroundFileName) ?? ""
```

In `encode(to:)`, after the `items` line:

```swift
        try container.encode(backgroundFileName, forKey: .backgroundFileName)
```

- [ ] **Step 4: Create the mutator file**

Create `MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel+Background.swift`:

```swift
import Foundation

// The page-background mutator (its own file for the CanvasViewModel
// size cap). Snapshots internally: one undo per call.
extension CanvasViewModel {
    /// Sets (or, with "", clears) the page's full-bleed background.
    public func setBackground(fileName: String) {
        beginChange()
        memory.backgroundFileName = fileName
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MemoryBackgroundTests 2>&1 | tail -3`
Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/Models.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel+Background.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MemoryBackgroundTests.swift
git commit -m "feat: give memories an optional page background

Refs #24

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Router -- background family + ImageChoicePlacement

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift` (outcome enum ~line 25-39, intent cases ~line 55-62, verb ~line 149-155, perform delegation ~line 206)
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift` (classify order, cues, performSlowImage, instantOutcome, isSlowImageWork)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraBackgroundIntentTests.swift` (create)

**Interfaces:**
- Consumes: `hasEditVerb`, existing generation cues, Task 1's names.
- Produces: `public enum ImageChoicePlacement: Equatable, Sendable { case picture, sticker, background }`; `MiraOutcome.imageChoices([Data], prompt: String, placement: ImageChoicePlacement)` (REPLACES the `sticker: Bool` shape); `MiraOutcome.backgroundCleared(MiraReceipt)`; intents `.setBackground(prompt: String)` / `.clearBackground` with verb "Painting the backdrop...". Task 3 relies on all of these exactly.

- [ ] **Step 1: Write the failing classification tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraBackgroundIntentTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraBackgroundIntentTests: XCTestCase {
    func testEnglishBackgroundAskSets() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("give this page a sunset background", editor: editor)
        guard case .setBackground(let prompt) = intent else {
            return XCTFail("expected setBackground, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("sunset"))
    }

    func testDrawWordStillGoesToBackgroundWhenMentioned() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("draw a starry background", editor: editor)
        guard case .setBackground = intent else {
            return XCTFail("expected setBackground, got \(intent)")
        }
    }

    func testChineseBackgroundAskSets() {
        let editor = CanvasViewModel(memory: Memory())
        // "huan ge xingkong beijing" -- switch to a starry background.
        let intent = MiraIntent.classify(
            "\u{6362}\u{4E2A}\u{661F}\u{7A7A}\u{80CC}\u{666F}", editor: editor)
        guard case .setBackground = intent else {
            return XCTFail("expected setBackground, got \(intent)")
        }
    }

    func testRemoveBackgroundClears() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        let intent = MiraIntent.classify("remove the background", editor: editor)
        guard case .clearBackground = intent else {
            return XCTFail("expected clearBackground, got \(intent)")
        }
    }

    func testChineseClearAsk() {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        // "qu diao beijing" -- remove the background.
        let intent = MiraIntent.classify("\u{53BB}\u{6389}\u{80CC}\u{666F}", editor: editor)
        guard case .clearBackground = intent else {
            return XCTFail("expected clearBackground, got \(intent)")
        }
    }

    func testPhotoBackgroundAskStaysOutOfTheFamily() {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addImages(
            [ImageRef(displayName: "p", fileName: "p.png")],
            around: CGPoint(x: 150, y: 100))
        let intent = MiraIntent.classify("remove the background of the photo", editor: editor)
        if case .setBackground = intent { XCTFail("photo asks must not set the page background") }
        if case .clearBackground = intent { XCTFail("photo asks must not clear the page background") }
    }

    func testStickerMentionStaysOut() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("give the sticker a new background", editor: editor)
        if case .setBackground = intent { XCTFail("sticker asks must not set the page background") }
    }

    func testPlainDrawStillGenerates() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("draw a paper crane", editor: editor)
        guard case .generateImage = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MiraBackgroundIntentTests 2>&1 | tail -4`
Expected: compile FAILURE -- no `setBackground` member.

- [ ] **Step 3: MiraIntent.swift changes**

(a) In `MiraOutcome`, REPLACE the imageChoices line and add the cleared case:

```swift
    case imageChoices([Data], prompt: String, placement: ImageChoicePlacement)
```

and after `textRecolored`:

```swift
    case backgroundCleared(MiraReceipt)
```

(b) Above `MiraOutcome`, add:

```swift
/// Where a picked image candidate lands.
public enum ImageChoicePlacement: Equatable, Sendable {
    case picture
    case sticker
    case background
}
```

(c) New intent cases after `clarifySticker`:

```swift
    case setBackground(prompt: String)
    case clearBackground
```

(d) `verb`: add before the instant-work line:

```swift
        case .setBackground: return "Painting the backdrop..."
```

and fold clearBackground into the instant group:

```swift
        case .applyFilter, .applyFrame, .resizeText, .recolorText, .clearBackground: return "Working..."
```

(e) `perform` delegation gains the two cases:

```swift
        case .generateImage, .editPhoto, .makeSticker, .applyFilter,
             .applyFrame, .resizeText, .recolorText, .clarifyPhoto,
             .editSticker, .clarifySticker, .setBackground, .clearBackground:
            return try await performImageOrStyle(imageStudio: imageStudio)
```

- [ ] **Step 4: MiraIntent+Image.swift changes**

(a) `isSlowImageWork`:

```swift
        case .generateImage, .editPhoto, .makeSticker, .editSticker, .setBackground: return true
```

(b) In `classifyImageOrStyle`, hoist the mention flags and check the background
family FIRST (a background ask often contains "draw"/"画"). The body becomes:

```swift
        let mentionsSticker = ["sticker", "\u{8D34}\u{7EB8}"].contains(where: lowered.contains)
        let stickerCut = lowered.contains("into a sticker")
            || lowered.contains("\u{62A0}\u{6210}")
        let mentionsPhoto = ["photo", "picture", "\u{7167}\u{7247}", "\u{56FE}"]
            .contains(where: lowered.contains)
        if !mentionsPhoto, !mentionsSticker,
           let background = backgroundIntent(lowered, prompt: prompt) {
            return background
        }
        if let generation = generationIntent(lowered, prompt: prompt) {
            return generation
        }
        // Mixed mentions ("make the photo look like the sticker",
        // "\u{628A}\u{7167}\u{7247}\u{53D8}\u{6210}\u{8D34}\u{7EB8}") stay
        // with the photo family: never redraw a sticker when the words
        // are about a photo.
        if !mentionsPhoto, let stickerEdit = stickerEditIntent(
            lowered, prompt: prompt, stickerCut: stickerCut,
            editor: editor, imageStore: imageStore
        ) {
            return stickerEdit
        }
        // A sticker-flavored ask must never mutate a photo ("make the
        // sticker warmer" used to land on the photo warm filter).
        if mentionsSticker && !mentionsPhoto && !stickerCut {
            return styleIntent(lowered, editor: editor)
        }
        if let photoIntent = photoIntent(
            lowered, prompt: prompt, mentionsPhoto: mentionsPhoto,
            editor: editor, imageStore: imageStore
        ) {
            return photoIntent
        }
        return styleIntent(lowered, editor: editor)
```

(c) Add the family helper (place before `generationIntent`):

```swift
    /// The page-background family ("give this page a sunset background",
    /// "\u{6362}\u{4E2A}\u{661F}\u{7A7A}\u{80CC}\u{666F}"). Callers must
    /// already have excluded photo- and sticker-flavored asks.
    private static func backgroundIntent(_ lowered: String, prompt: String) -> MiraIntent? {
        let mentions = ["background", "backdrop", "\u{80CC}\u{666F}", "\u{5E95}\u{8272}"]
            .contains(where: lowered.contains)
        guard mentions else { return nil }
        let clears = ["remove the background", "no background", "default background",
                      "clear the background",
                      "\u{53BB}\u{6389}\u{80CC}\u{666F}", "\u{6E05}\u{7A7A}\u{80CC}\u{666F}"]
        if clears.contains(where: lowered.contains) {
            return .clearBackground
        }
        let generationCues = ["draw ", "paint ", "generate ", "\u{753B}",
                              "\u{751F}\u{6210}", "\u{6765}\u{4E00}\u{5F20}", "\u{6765}\u{4E2A}"]
        guard hasEditVerb(lowered) || generationCues.contains(where: lowered.contains) else {
            return nil
        }
        return .setBackground(prompt: prompt)
    }
```

(d) In `performSlowImage`, change the generateImage return to the placement
shape and add setBackground before `default:`:

```swift
        case .generateImage(let prompt, let sticker):
            let images = try await imageStudio.generate(
                kind: sticker ? .sticker : .background, prompt: prompt)
            guard !images.isEmpty else { throw MiraTimeoutError() }
            return .imageChoices(Array(images.prefix(2)), prompt: prompt,
                                 placement: sticker ? .sticker : .picture)
```

```swift
        case .setBackground(let prompt):
            let images = try await imageStudio.generate(kind: .background, prompt: prompt)
            guard !images.isEmpty else { throw MiraTimeoutError() }
            return .imageChoices(Array(images.prefix(2)), prompt: prompt,
                                 placement: .background)
```

(e) In `instantOutcome`, add before `default:`:

```swift
        case .clearBackground:
            return .backgroundCleared(MiraReceipt(
                changed: "Cleared the background.",
                kept: "Undo restores it."))
```

- [ ] **Step 5: Fix the two existing pattern bindings that used `sticker:`**

The compiler will fail on `MiraCanvasCoordinator.swift`/`+Images.swift` until
Task 3; to keep THIS task compiling, Task 3's phase/settle changes land
together with it -- run the classification tests only after Task 3's Step 3
(they share one commit boundary if needed). If you prefer strict separation,
apply Task 3 Steps 3-4 now and commit both tasks as their own commits anyway
(tests gate each).

- [ ] **Step 6: Run the classification tests (after Task 3 Steps 3-4 compile)**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter "MiraBackgroundIntentTests|MiraImageIntentTests|MiraStickerIntentTests" 2>&1 | tail -3`
Expected: all PASS (8 new; every existing routing test still green).

- [ ] **Step 7: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraBackgroundIntentTests.swift
git commit -m "feat: route background asks through zhaoyan's pipeline

Refs #24

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Coordinator -- placement landing and clear settle

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator.swift` (MiraTurnPhase ~line 17; settle collapsed case ~line 316)
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift` (settleImageOutcome, placeImageChoice)
- Modify: `MiraNoteKit/Tests/MiraNoteKitTests/MiraImageTurnTests.swift` (two bindings)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraBackgroundTurnTests.swift` (create)

**Interfaces:**
- Consumes: Task 2's `ImageChoicePlacement`, `.backgroundCleared`, imageChoices placement shape; Task 1's `setBackground(fileName:)`.
- Produces: `MiraTurnPhase.imageChoices([Data], prompt: String, placement: ImageChoicePlacement)` -- Task 4's MiraStrip reads `placement`.

- [ ] **Step 1: Write the failing turn tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraBackgroundTurnTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraBackgroundTurnTests: XCTestCase {
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-bg-\(UUID().uuidString)")
    }

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

    func testBackgroundAskYieldsChoicesAndPlacingSetsIt() async {
        let dir = tempDir
        let editor = CanvasViewModel(memory: Memory())
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("give this page a sunset background", editor: editor)
        await waitUntil { if case .imageChoices = coordinator.phase { return true } else { return false } }
        guard case .imageChoices(let images, _, let placement) = coordinator.phase else {
            return XCTFail("expected imageChoices, got \(coordinator.phase)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(placement, .background)
        XCTAssertTrue(editor.memory.backgroundFileName.isEmpty, "nothing lands until a tap")

        coordinator.placeImageChoice(1, editor: editor)
        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected a receipt, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Set the page background.")
        XCTAssertEqual(
            ImageFileStore(directory: dir).data(forFileName: editor.memory.backgroundFileName),
            Data("img-B".utf8),
            "the SECOND candidate became the background")
        XCTAssertTrue(editor.items.isEmpty, "no canvas element was added")

        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "", "one undo removes it")
    }

    func testClearAskRemovesTheBackgroundWithOneUndo() async {
        let editor = CanvasViewModel(memory: Memory(backgroundFileName: "bg.png"))
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("remove the background", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .receipt(let receipt) = coordinator.phase else {
            return XCTFail("expected a receipt, got \(coordinator.phase)")
        }
        XCTAssertEqual(receipt.changed, "Cleared the background.")
        XCTAssertEqual(editor.memory.backgroundFileName, "")
        editor.undo()
        XCTAssertEqual(editor.memory.backgroundFileName, "bg.png")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MiraBackgroundTurnTests 2>&1 | tail -4`
Expected: compile FAILURE (placement shape not in the phase yet).

- [ ] **Step 3: Update the phase and settle**

(a) `MiraCanvasCoordinator.swift` line ~17:

```swift
    /// Two generated candidates awaiting the user's pick (or the xmark).
    case imageChoices([Data], prompt: String, placement: ImageChoicePlacement)
```

(b) Same file, the collapsed settle case gains backgroundCleared:

```swift
        case .imageChoices, .imageReplaced, .stickerReplaced, .stickerEdited,
             .filterApplied, .frameApplied, .textResized, .textRecolored,
             .backgroundCleared:
            settleImageOutcome(outcome, editor: editor)
```

(c) `MiraCanvasCoordinator+Images.swift`, `settleImageOutcome`:

```swift
        case .imageChoices(let images, let prompt, let placement):
            phase = .imageChoices(images, prompt: prompt, placement: placement)
```

and add before `default:`:

```swift
        case .backgroundCleared(let receipt):
            editor.setBackground(fileName: "")
            showReceipt(receipt, editor: editor)
```

(d) Same file, `placeImageChoice` becomes placement-driven:

```swift
    /// Tap on candidate `index`: write the file, land it, receipt.
    public func placeImageChoice(_ index: Int, editor: CanvasViewModel) {
        guard case .imageChoices(let images, let prompt, let placement) = phase,
              images.indices.contains(index),
              let fileName = try? imageStore.save(images[index], id: UUID())
        else { return }
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 90, 4000))
        switch placement {
        case .sticker:
            let generated = GeneratedSticker(
                prompt: prompt, symbolName: "sparkles", fileName: fileName)
            editor.addSticker(generated, at: position)
            stickerFavorites.add(generated)
            showReceipt(MiraReceipt(
                changed: "Added a sticker.",
                kept: "Everything else is untouched."), editor: editor)
        case .picture:
            editor.addImages(
                [ImageRef(displayName: prompt, fileName: fileName)],
                around: position)
            showReceipt(MiraReceipt(
                changed: "Added a picture.",
                kept: "Everything else is untouched."), editor: editor)
        case .background:
            editor.setBackground(fileName: fileName)
            showReceipt(MiraReceipt(
                changed: "Set the page background.",
                kept: "Everything else is untouched."), editor: editor)
        }
    }
```

- [ ] **Step 4: Update the two old bindings in MiraImageTurnTests.swift**

In `testGenerateAskYieldsTwoChoices`, replace

```swift
        guard case .imageChoices(let images, _, let sticker) = coordinator.phase else {
            return XCTFail("expected imageChoices, got \(coordinator.phase)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertFalse(sticker)
```

with

```swift
        guard case .imageChoices(let images, _, let placement) = coordinator.phase else {
            return XCTFail("expected imageChoices, got \(coordinator.phase)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(placement, .picture)
```

(The other tests in that file match `.imageChoices` without bindings and
compile unchanged.)

- [ ] **Step 5: Run the Kit suite**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | grep -E "Executed.*failures" | tail -1`
Expected: 186+ tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraImageTurnTests.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraBackgroundTurnTests.swift
git commit -m "feat: land picked background candidates on the page

Refs #24

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: UI -- PageBackdrop, palette, thumbs, UITests

**Files:**
- Create: `App/Sources/Screens/Editor/PageBackdrop.swift`
- Modify: `App/Sources/DesignSystem/Palette.swift` (after `paper`, ~line 13)
- Modify: `App/Sources/Screens/Editor/CanvasBoardView.swift` (`paper`, ~line 113)
- Modify: `App/Sources/Screens/Reading/PageRendering.swift` (backdrop, ~line 23)
- Modify: `App/Sources/Screens/Editor/MiraStrip.swift` (choices card ~line 99, choiceThumb ~line 128)
- Test: `App/UITests/BackgroundUITests.swift` (create)

**Interfaces:**
- Consumes: `Memory.backgroundFileName`, `MiraTurnPhase.imageChoices(..., placement:)`.
- Produces: `PageBackdrop(backgroundFileName: String)` view; `Palette.backdropDawn/backdropDusk`.

- [ ] **Step 1: Write the failing UI tests**

Create `App/UITests/BackgroundUITests.swift`:

```swift
import XCTest

/// Page background asks (deterministic under -UITEST).
final class BackgroundUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

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

    func testBackgroundAskPlacesViaChoices() {
        startMemory()
        ask("give this page a sunset background")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "two candidates arrive")
        first.tap()
        XCTAssertTrue(app.staticTexts["Set the page background."].waitForExistence(timeout: 5))
    }

    func testClearBackgroundReceipts() {
        startMemory()
        ask("remove the background")
        XCTAssertTrue(app.staticTexts["Cleared the background."].waitForExistence(timeout: 8))
    }
}
```

- [ ] **Step 2: Run one to verify it fails**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcodegen generate
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  -only-testing:MiraNoteUITests/BackgroundUITests/testBackgroundAskPlacesViaChoices 2>&1 | tail -4
```
Expected: FAIL (no receipt "Set the page background." -- Tasks 1-3 not yet in the app? They are, so this may PASS already except the receipt copy assertion is exact; if it passes, note it and continue). The clear test may also pass. These UITests primarily pin the end-to-end wiring.

- [ ] **Step 3: Palette + PageBackdrop**

`App/Sources/DesignSystem/Palette.swift`, after the `paper` line:

```swift
    static let backdropDawn = Color(hex: 0xF0B78E)
    static let backdropDusk = Color(hex: 0x702E4E)
```

Create `App/Sources/Screens/Editor/PageBackdrop.swift`:

```swift
import MiraNoteKit
import SwiftUI

/// The page's full-bleed backdrop, shared by the editor and the static
/// renderers: the stored background image when the page has one, else
/// the default dawn-to-dusk gradient (mockup, 2026-07-11). A missing
/// file falls back to the gradient -- never a hole.
struct PageBackdrop: View {
    let backgroundFileName: String

    private let imageStore = ImageFileStore()

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [Palette.backdropDawn, Palette.backdropDusk],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(backgroundImage)
    }

    @ViewBuilder private var backgroundImage: some View {
        if !backgroundFileName.isEmpty,
           let data = imageStore.data(forFileName: backgroundFileName),
           let image = UIImage(data: data) {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
    }
}
```

- [ ] **Step 4: Consume it in both surfaces**

`CanvasBoardView.swift`, `paper` (line ~113) -- the fill becomes the backdrop,
border and tap stay:

```swift
    /// The page itself -- its backdrop stretches with the content, so the
    /// background never "runs out".
    private var paper: some View {
        PageBackdrop(backgroundFileName: editor.memory.backgroundFileName)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
            )
            .onTapGesture {
                editor.endEditingText()
                editor.select(nil)
                textFocus.wrappedValue = nil
            }
    }
```

`PageRendering.swift` (line ~23), replace the RoundedRectangle+fill with:

```swift
            PageBackdrop(backgroundFileName: memory.backgroundFileName)
```

- [ ] **Step 5: MiraStrip 9:16 thumbs**

Replace the choices case binding and thumb (placement drives the shape):

```swift
        case .imageChoices(let images, _, let placement):
            // Two candidates, the human picks ("AI offers, the human
            // shapes"); the xmark discards both without touching paper.
            card {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                        Button {
                            coordinator.placeImageChoice(index, editor: editor)
                        } label: {
                            choiceThumb(for: data, tall: placement == .background)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mira.imageChoice.\(index)")
                    }
```

and

```swift
    @ViewBuilder private func choiceThumb(for data: Data, tall: Bool) -> some View {
        let width: CGFloat = tall ? 64 : 84
        let height: CGFloat = tall ? 114 : 84
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.tan.opacity(0.4))
                .frame(width: width, height: height)
        }
    }
```

- [ ] **Step 6: Run both UITests on the shadow simulator**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcodegen generate
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  -only-testing:MiraNoteUITests/BackgroundUITests 2>&1 | grep -E "Test Case '|TEST" | tail -5
```
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add App/Sources/Screens/Editor/PageBackdrop.swift \
        App/Sources/DesignSystem/Palette.swift \
        App/Sources/Screens/Editor/CanvasBoardView.swift \
        App/Sources/Screens/Reading/PageRendering.swift \
        App/Sources/Screens/Editor/MiraStrip.swift \
        App/UITests/BackgroundUITests.swift
git commit -m "feat: render page backgrounds behind every surface

Refs #24

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Gates, live film-strip, PR

- [ ] **Step 1: Lint from the repo root**

Run: `cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict 2>&1 | tail -1`
Expected: 0 violations (split files if a cap trips, repo pattern).

- [ ] **Step 2: Full Kit suite + full app suites (shadow sim)**

```bash
cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | grep -E "Executed.*failures" | tail -1
cd /Users/mengjia/MiraNote/miranote-ios
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' 2>&1 | grep -E "TEST" | tail -2
```
Expected: 0 failures / TEST SUCCEEDED.

- [ ] **Step 3: Live film-strip against :8002**

Throwaway probe (never committed): launch live, "give this page a sunset gradient background" -> wait for choices (150 s budget) -> place -> screenshot strip: candidates are full-bleed 9:16, the page fills edge-to-edge under items, undo restores the default gradient. Delete the probe, `xcodegen generate` after deletion.

- [ ] **Step 4: Push and open the PR**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git push -u origin feat/page-backgrounds
gh pr create --repo MiraNote-AI/miranote-ios \
  --title "feat(ios): give pages ai backgrounds over a new default" \
  --body "$(cat <<'EOF'
Closes #24. Spec: docs/specs/2026-07-11-page-backgrounds-design.md (in this PR).

## What

- Memory gains backgroundFileName (decodeIfPresent; old saves render
  the new default). One shared PageBackdrop view paints the editor,
  reading mode, covers, and export: stored image full-bleed, else the
  new dawn-to-dusk default gradient (mockup, 2026-07-11).
- Mira background family: "give this page a sunset background" /
  Chinese equivalents run the previously-unused :8002 background
  command (Zhaoyan's pipeline) and land through the two-candidate
  picker (9:16 thumbs); "remove the background" clears instantly.
  One undo each; persists with the page.
- The picker generalizes from a sticker flag to
  ImageChoicePlacement (picture/sticker/background).

## Why this approach

Both halves were decided with Meng on 2026-07-11 against the provided
mockup. The generic-picture misuse of the background command is NOT
fixed here (needs a new api command; follow-up issue).

## Not verified

- HUMAN: default-gradient taste and ink-text legibility on the darker
  lower half (deviation from the 7/8 walkthrough, decided by Meng).
- HUMAN: whether live pipeline output reads as "a background" across
  many prompts; one live pass looked right.
EOF
)"
```
Expected: PR URL; CI green; human merges.

## Iterations

(Ledger: one line per act+verify cycle.)

1. Task 1 model+mutator -- red exposed that undo history snapshotted only items; history generalized to UndoSnapshot (items + backgroundFileName), 4/4 green, full Kit 176/176 (deviation from plan, recorded in the commit).
2. Tasks 2+3 router+landing (compiled together per plan note) -- 186/186 green including the two updated bindings.
3. Task 4 UI -- both UITests green on first run after xcodegen.
4. Task 5 gates -- lint 2 -> 0 (CanvasViewModel+Sound.swift split; generateChoices extraction for complexity); full app suites SUCCEEDED; live :8002 probe passed in 30 s -- real sunset background landed full-bleed, receipt + Revert shown, undo restored the new default gradient (film-strip f024/f026/f028).
