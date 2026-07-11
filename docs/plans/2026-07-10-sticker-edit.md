# Sticker Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sticker already on the canvas can be restyled with words, from the Mira ask bar and from a new long-press Edit sticker panel, in place, with one undo.

**Architecture:** Extend the local cue router (MiraIntent) with an editSticker family gated on DEFINITE sticker mentions, resolve targets like photos (selected, else only, else clarify), run stylize -> cutout -> outline on the existing :8002 pipeline, and land through the existing stickerReplaced outcome via a new CanvasViewModel.replaceSticker mutator. The UI side is one context-menu entry plus a one-field panel copying PhotoEditPanel's Ask AI row.

**Tech Stack:** SwiftUI, MiraNoteKit (SPM), XCTest, swiftlint. Backend untouched (spec: docs/specs/2026-07-10-sticker-edit-design.md). Refs #21.

## Global Constraints

- Org Rule 3: committed Swift source stays ASCII -- Chinese cues are written as unicode escapes like "\u{8D34}\u{7EB8}" (docs/plans and docs/specs are exempt).
- swiftlint --strict must report 0 (file cap 400 lines, type body 250, function body 50).
- Test suites run ONLY on the shadow simulator 35B7DA99-2D8B-4E9D-9848-FE17661F0B59, never on the user simulator 6E165F5B-C411-40B4-A1A7-940E548D0D21.
- Every editor mutator snapshots internally via beginChange(); never wrap a mutator call in another beginChange.
- Branch feat/sticker-edit, base main, PR references issue #21; a human merges.
- Copy strings (receipts, clarify questions, panel notices) are exactly the ones in this plan -- they are asserted by tests and match the spec.

---

### Task 1: Intent surface -- editSticker / clarifySticker in the cue router

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift`
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerIntentTests.swift` (create)

**Interfaces:**
- Consumes: `MiraIntent.classifyImageOrStyle`, `ImageFileStore.data(forFileName:)`, `CanvasViewModel.orderedItems/selectedItemID/addSticker`.
- Produces (Tasks 2-3 rely on these exact shapes):
  - `case editSticker(CanvasItem.ID, imageData: Data, instruction: String, prompt: String)`
  - `case clarifySticker(question: String)`
  - `static func stickerTarget(editor: CanvasViewModel) -> StickerTarget` with `enum StickerTarget { case one(CanvasItem.ID, GeneratedSticker); case none; case ambiguous }`
  - editSticker's perform returns `.stickerReplaced(id, outlined, prompt:, receipt)` with receipt "Restyled the sticker." / "Undo brings the old one back.".

- [ ] **Step 1: Write the failing classification tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerIntentTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraStickerIntentTests: XCTestCase {
    /// Stickers land first (ids captured per add); optionally one photo
    /// after them, optionally the FIRST sticker selected.
    private func editorWithStickers(
        _ count: Int, selectFirst: Bool = false, addPhoto: Bool = false
    ) -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        var first: CanvasItem.ID?
        for index in 0..<count {
            editor.addSticker(
                GeneratedSticker(prompt: "cat \(index)", symbolName: "sparkles",
                                 fileName: "s\(index).png"),
                at: CGPoint(x: 150, y: 100 + CGFloat(index) * 200)
            )
            if index == 0 { first = editor.items.last?.id }
        }
        if addPhoto {
            _ = editor.addImages(
                [ImageRef(displayName: "photo", fileName: "p.png")],
                around: CGPoint(x: 150, y: 700)
            )
        }
        if selectFirst, let first { editor.select(first) }
        return editor
    }

    func testEnglishEditCueEditsTheOnlySticker() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .editSticker(_, _, let instruction, let prompt) = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
        XCTAssertTrue(instruction.contains("blue"))
        XCTAssertEqual(prompt, "cat 0", "the original label rides along")
    }

    func testChineseEditCueEditsTheOnlySticker() {
        let editor = editorWithStickers(1)
        // "ba tiezhi gaicheng lanse" -- change the sticker to blue.
        let intent = MiraIntent.classify(
            "\u{628A}\u{8D34}\u{7EB8}\u{6539}\u{6210}\u{84DD}\u{8272}", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testSelectedStickerWinsWhenSeveral() {
        let editor = editorWithStickers(2, selectFirst: true)
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .editSticker(let id, _, _, _) = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
        XCTAssertEqual(id, editor.selectedItemID)
    }

    func testSeveralUnselectedStickersClarify() {
        let editor = editorWithStickers(2)
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .clarifySticker(let question) = intent else {
            return XCTFail("expected clarifySticker, got \(intent)")
        }
        XCTAssertTrue(question.contains("tap the one you mean"))
    }

    func testZeroStickersClarify() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("make the sticker blue", editor: editor)
        guard case .clarifySticker(let question) = intent else {
            return XCTFail("expected clarifySticker, got \(intent)")
        }
        XCTAssertTrue(question.contains("No sticker"))
    }

    func testIndefiniteStickerWishStaysConverse() {
        let editor = editorWithStickers(1)
        let intent = MiraIntent.classify("make a sticker of a cat", editor: editor)
        guard case .converse = intent else {
            return XCTFail("expected converse, got \(intent)")
        }
    }

    func testStickerWarmerNeverTouchesThePhoto() {
        let editor = editorWithStickers(1, addPhoto: true)
        let intent = MiraIntent.classify("make the sticker warmer", editor: editor)
        guard case .editSticker = intent else {
            return XCTFail("expected editSticker, got \(intent)")
        }
    }

    func testPhotoCutoutPhraseStillConvertsThePhoto() {
        let editor = editorWithStickers(1, addPhoto: true)
        // "ba zhaopian koucheng tiezhi" -- cut the photo into a sticker.
        let intent = MiraIntent.classify(
            "\u{628A}\u{7167}\u{7247}\u{62A0}\u{6210}\u{8D34}\u{7EB8}", editor: editor)
        guard case .makeSticker = intent else {
            return XCTFail("expected makeSticker, got \(intent)")
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MiraStickerIntentTests 2>&1 | tail -5`
Expected: compile FAILURE -- `editSticker`/`clarifySticker` are not members of MiraIntent.

- [ ] **Step 3: Add the cases and switch arms in MiraIntent.swift**

In `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift`:

(a) After `case clarifyPhoto`:

```swift
    case editSticker(CanvasItem.ID, imageData: Data, instruction: String, prompt: String)
    case clarifySticker(question: String)
```

(b) In `var verb`, add before the instant-work line, and fold clarifySticker into the last line:

```swift
        case .editSticker: return "Redrawing the sticker..."
        // Instant local work settles before the 400 ms delay ever shows it.
        case .applyFilter, .applyFrame, .resizeText, .recolorText: return "Working..."
        case .clarifyPhoto, .clarifySticker: return "Thinking..."
```

(c) In `var affectedItems`, add to the id-carrying pattern list (after `.recolorText(let id, _)`):

```swift
             .recolorText(let id, _),
             .editSticker(let id, _, _, _):
```

(d) In `perform`, extend the delegated group:

```swift
        case .generateImage, .editPhoto, .makeSticker, .applyFilter,
             .applyFrame, .resizeText, .recolorText, .clarifyPhoto,
             .editSticker, .clarifySticker:
            return try await performImageOrStyle(imageStudio: imageStudio)
```

- [ ] **Step 4: Add targeting, cues, and the pipeline in MiraIntent+Image.swift**

(a) `isSlowImageWork` gains editSticker:

```swift
        case .generateImage, .editPhoto, .makeSticker, .editSticker: return true
```

(b) In `performSlowImage`, insert before `default:`:

```swift
        case .editSticker(let id, let data, let instruction, let prompt):
            guard !data.isEmpty else {
                throw MiraClarifyError(
                    question: "This sticker has no stored pixels to work on -- try another?",
                    chips: []
                )
            }
            let styled = try await imageStudio.stylize(image: data, instruction: instruction)
            let cut = try await imageStudio.cutout(image: styled, target: nil)
            let outlined = try await imageStudio.outline(image: cut)
            return .stickerReplaced(id, outlined, prompt: prompt, MiraReceipt(
                changed: "Restyled the sticker.",
                kept: "Undo brings the old one back."))
        case .clarifySticker(let question):
            throw MiraClarifyError(question: question, chips: [])
```

(c) Replace the body of `classifyImageOrStyle` with (generation unchanged; sticker family second; guard before the photo family):

```swift
        if let generation = generationIntent(lowered, prompt: prompt) {
            return generation
        }
        let mentionsSticker = ["sticker", "\u{8D34}\u{7EB8}"].contains(where: lowered.contains)
        let stickerCut = lowered.contains("into a sticker")
            || lowered.contains("\u{62A0}\u{6210}")
        if let stickerEdit = stickerEditIntent(
            lowered, prompt: prompt, stickerCut: stickerCut,
            editor: editor, imageStore: imageStore
        ) {
            return stickerEdit
        }
        let mentionsPhoto = ["photo", "picture", "\u{7167}\u{7247}", "\u{56FE}"]
            .contains(where: lowered.contains)
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

Note: `photoIntent` still computes its own stickerCut internally -- leave it untouched.

(d) Add the new target enum and helpers (place after `photoTarget`):

```swift
    enum StickerTarget {
        case one(CanvasItem.ID, GeneratedSticker)
        case none
        case ambiguous
    }

    /// Selected sticker first; else the only sticker; else ambiguous.
    @MainActor
    static func stickerTarget(editor: CanvasViewModel) -> StickerTarget {
        let stickers = editor.orderedItems.compactMap { item -> (CanvasItem.ID, GeneratedSticker)? in
            guard case .sticker(let sticker) = item.content else { return nil }
            return (item.id, sticker)
        }
        if let selected = editor.selectedItemID,
           let match = stickers.first(where: { $0.0 == selected }) {
            return .one(match.0, match.1)
        }
        if stickers.count == 1, let only = stickers.first {
            return .one(only.0, only.1)
        }
        return stickers.isEmpty ? .none : .ambiguous
    }

    /// In-place sticker edit: a DEFINITE sticker mention ("the sticker",
    /// never "a sticker" -- that wishes for a new one) plus an edit verb,
    /// and not the photo-conversion phrase ("into a sticker").
    @MainActor
    private static func stickerEditIntent(
        _ lowered: String, prompt: String, stickerCut: Bool,
        editor: CanvasViewModel, imageStore: ImageFileStore
    ) -> MiraIntent? {
        let definite = ["the sticker", "this sticker", "that sticker",
                        "my sticker", "\u{8D34}\u{7EB8}"]
            .contains(where: lowered.contains)
        let editVerb = lowered.contains("make ") || lowered.contains("\u{628A}")
        guard definite, editVerb, !stickerCut else { return nil }
        switch stickerTarget(editor: editor) {
        case .none:
            return .clarifySticker(
                question: "No sticker on this page yet -- generate one first?")
        case .ambiguous:
            return .clarifySticker(
                question: "More than one sticker here -- tap the one you mean and ask again.")
        case .one(let id, let sticker):
            let data = imageStore.data(forFileName: sticker.fileName) ?? Data()
            return .editSticker(id, imageData: data, instruction: prompt,
                                prompt: sticker.prompt)
        }
    }
```

- [ ] **Step 5: Run the new tests and the neighboring suites**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter "MiraStickerIntentTests|MiraImageIntentTests|MiraImageTurnTests" 2>&1 | tail -5`
Expected: all PASS (8 new + 12 + 9 existing; the guard must not break any photo test).

- [ ] **Step 6: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerIntentTests.swift
git commit -m "feat: route definite sticker asks to an edit intent

Refs #21

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Landing -- replaceSticker mutator and the settle branch

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel.swift` (after `replaceImageWithSticker`, ~line 262)
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift` (`settleStickerReplaced`, ~line 106)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerTurnTests.swift` (create)

**Interfaces:**
- Consumes: Task 1's editSticker intent and stickerReplaced outcome; `ScriptedImageStudio` (defined in MiraImageTurnTests.swift, same module: stylize -> "styled", cutout -> "cut", outline -> "outlined"); `MiraCanvasCoordinator` init with `imageStore:`/`stickerFavorites:` (sets `MiraIntent.classifyImageStore` internally).
- Produces: `CanvasViewModel.replaceSticker(itemID:with:)` -- guards the item is a `.sticker`, snapshots via beginChange(), swaps content. Task 3's panel calls it.

- [ ] **Step 1: Write the failing turn tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerTurnTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraStickerTurnTests: XCTestCase {
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-sticker-\(UUID().uuidString)")
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

    private func placeSticker(in editor: CanvasViewModel, store: ImageFileStore) throws -> CanvasItem.ID {
        let fileName = try store.save(Data("orig".utf8), id: UUID())
        editor.addSticker(
            GeneratedSticker(prompt: "the cat", symbolName: "sparkles", fileName: fileName),
            at: CGPoint(x: 150, y: 100)
        )
        return editor.items.last!.id
    }

    func testEditReplacesPixelsInPlaceThroughTheFullCut() async throws {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let favorites = StickerFavoritesStore(url: dir.appendingPathComponent("favs.json"))
        let editor = CanvasViewModel(memory: Memory())
        let id = try placeSticker(in: editor, store: store)
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }
        guard case .sticker(let sticker) = editor.item(id)!.content else {
            return XCTFail("expected the item to stay a sticker")
        }
        XCTAssertEqual(store.data(forFileName: sticker.fileName), Data("outlined".utf8),
                       "stylize -> cutout -> outline ran to the end")
        XCTAssertEqual(sticker.prompt, "the cat", "the label survives the edit")
        XCTAssertEqual(favorites.all().count, 1, "the edited sticker is reusable")
    }

    func testOneUndoRestoresTheOldSticker() async throws {
        let dir = tempDir
        let store = ImageFileStore(directory: dir)
        let editor = CanvasViewModel(memory: Memory())
        let id = try placeSticker(in: editor, store: store)
        let coordinator = makeCoordinator(tempDir: dir)
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .receipt = coordinator.phase { return true } else { return false } }

        editor.undo()
        guard case .sticker(let restored) = editor.item(id)!.content else {
            return XCTFail("expected a sticker after undo")
        }
        XCTAssertEqual(store.data(forFileName: restored.fileName), Data("orig".utf8),
                       "one undo brings the old pixels back")
    }

    func testMissingPixelsFailCalmly() async {
        let editor = CanvasViewModel(memory: Memory())
        editor.addSticker(
            GeneratedSticker(prompt: "ghost", symbolName: "sparkles", fileName: "missing.png"),
            at: CGPoint(x: 150, y: 100)
        )
        let coordinator = makeCoordinator(tempDir: tempDir)
        coordinator.ask("make the sticker blue", editor: editor)
        await waitUntil { if case .failure = coordinator.phase { return true } else { return false } }
        guard case .failure = coordinator.phase else {
            return XCTFail("expected the calm clarify card, got \(coordinator.phase)")
        }
        XCTAssertEqual(editor.items.count, 1, "canvas untouched")
    }
}
```

- [ ] **Step 2: Run them to verify the interesting failure**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MiraStickerTurnTests 2>&1 | tail -8`
Expected: testEditReplacesPixelsInPlaceThroughTheFullCut FAILS -- settleStickerReplaced still calls replaceImageWithSticker, which guards on `.image` and silently no-ops on a sticker item, so the receipt shows but `store.data(...) == "outlined"` is false. testMissingPixelsFailCalmly passes already (the guard is Task 1 code), and testOneUndoRestoresTheOldSticker passes vacuously (nothing changed, so "orig" is still there) -- it becomes a real regression guard once Step 3-4 land.

- [ ] **Step 3: Add the mutator**

In `MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel.swift`, directly after `replaceImageWithSticker` (line ~262):

```swift
    public func replaceSticker(itemID: CanvasItem.ID, with sticker: GeneratedSticker) {
        guard let index = index(of: itemID),
              case .sticker = memory.items[index].content else { return }
        beginChange()
        memory.items[index].content = .sticker(sticker)
    }
```

- [ ] **Step 4: Branch the settle on the target's current content**

In `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift`, replace `settleStickerReplaced` with:

```swift
    private func settleStickerReplaced(_ id: CanvasItem.ID, data: Data, prompt: String,
                                       receipt: MiraReceipt, editor: CanvasViewModel) {
        guard let item = editor.item(id),
              let fileName = try? imageStore.save(data, id: UUID()) else {
            phase = .failure(MiraFailure(
                kind: .retry,
                message: "The photo I was working on is gone, so I left everything as is.",
                chips: ["Try again"]))
            return
        }
        let sticker = GeneratedSticker(prompt: prompt, symbolName: "sparkles",
                                       fileName: fileName)
        if case .sticker = item.content {
            editor.replaceSticker(itemID: id, with: sticker)
        } else {
            editor.replaceImageWithSticker(itemID: id, sticker: sticker)
        }
        stickerFavorites.add(sticker)
        showReceipt(receipt, editor: editor)
    }
```

- [ ] **Step 5: Run the turn tests plus the photo-conversion neighbors**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter "MiraStickerTurnTests|MiraImageTurnTests" 2>&1 | tail -5`
Expected: all PASS (the `.image` branch keeps testMakeStickerReplacesInPlaceAndJoinsFavorites green).

- [ ] **Step 6: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraStickerTurnTests.swift
git commit -m "feat: land sticker edits in place with one undo

Refs #21

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: UI -- Edit sticker menu entry and panel

**Files:**
- Create: `App/Sources/Screens/Editor/StickerEditPanel.swift`
- Modify: `App/Sources/Screens/Editor/CanvasBoardView.swift` (callback ~line 18; context menu `.sticker` branch ~line 313)
- Modify: `App/Sources/Screens/Editor/CanvasScene.swift` (state ~line 25; board init ~line 45; bottom cluster ~line 141; changeCount observer ~line 81; handleTool ~line 196)
- Test: `App/UITests/StickerEditUITests.swift` (create)

**Interfaces:**
- Consumes: Task 2's `CanvasViewModel.replaceSticker(itemID:with:)`; `ImageStudioService.stylize/cutout/outline`; `ImageFileStore`, `StickerFavoritesStore.forCurrentProcess()`, `ContextCard`, `Palette`, `Metrics` (all existing, used the same way in PhotoEditPanel.swift).
- Produces: accessibility ids `sticker.ai.instruction`, `sticker.ai.run`, `sticker.done`; menu button labeled "Edit sticker"; panel notice copy "Done -- take a look. Undo brings the old one back.".

- [ ] **Step 1: Write the failing UI tests**

Create `App/UITests/StickerEditUITests.swift`:

```swift
import XCTest

/// Editing a placed sticker: the Mira ask and the long-press panel
/// (deterministic under -UITEST: the mock studio answers instantly).
final class StickerEditUITests: XCTestCase {
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

    /// Draw-and-place one sticker, then wait out the placement receipt
    /// so the next step starts from a quiet strip.
    private func placeOneSticker() {
        ask("draw a sticker of a coffee cup")
        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        let receipt = app.staticTexts["mira.receipt"]
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 12), .completed,
                       "the placement receipt clears")
    }

    func testAskRestylesThePlacedSticker() {
        startMemory()
        placeOneSticker()

        ask("make the sticker blue")
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 8),
                      "the edit lands with a receipt")
        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        XCTAssertTrue(sticker.exists, "the element is still a sticker")
    }

    func testLongPressPanelEditsTheSticker() {
        startMemory()
        placeOneSticker()

        let sticker = app.descendants(matching: .any)
            .matching(identifier: "element.sticker").firstMatch
        sticker.press(forDuration: 1.1)
        let entry = app.buttons["Edit sticker"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "the menu gains Edit sticker")
        entry.tap()

        let field = app.textFields["sticker.ai.instruction"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make it blue")
        app.buttons["sticker.ai.run"].tap()
        XCTAssertTrue(
            app.staticTexts["Done -- take a look. Undo brings the old one back."]
                .waitForExistence(timeout: 8),
            "the panel reports the swap"
        )
    }
}
```

- [ ] **Step 2: Run one of them to verify it fails**

Run:
```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  -only-testing:MiraNoteUITests/StickerEditUITests/testLongPressPanelEditsTheSticker \
  2>&1 | tail -5
```
Expected: FAIL at `app.buttons["Edit sticker"]` -- the menu entry does not exist yet. (If Xcode does not pick up the new file automatically, the target uses folder-synchronized groups; a file added under App/UITests/ is picked up on build.)

- [ ] **Step 3: Add the callback and menu entry in CanvasBoardView.swift**

(a) After `var onEditImage: (CanvasItem.ID) -> Void = { _ in }` (line 18):

```swift
    var onEditSticker: (CanvasItem.ID) -> Void = { _ in }
```

(b) Replace `case .sticker: EmptyView()` (line ~313) with:

```swift
        case .sticker(let sticker):
            if !sticker.fileName.isEmpty {
                Button {
                    onEditSticker(item.id)
                } label: {
                    Label("Edit sticker", systemImage: "wand.and.stars")
                }
            }
```

- [ ] **Step 4: Create StickerEditPanel.swift**

```swift
import MiraNoteKit
import SwiftUI

/// The on-canvas sticker edit panel: one instruction, then the same
/// pipeline as make-sticker (stylize -> cutout -> outline) so the
/// die-cut look survives shape changes. Replaces in place; one undo.
struct StickerEditPanel: View {
    @Bindable var editor: CanvasViewModel
    let itemID: CanvasItem.ID
    var studio: ImageStudioService
    var onClose: () -> Void

    @State private var instruction = ""
    @State private var editing = false
    @State private var notice: String?

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        ContextCard(title: "Edit sticker") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("Tell AI what to change", text: $instruction)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.forest)
                        .accessibilityIdentifier("sticker.ai.instruction")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Palette.paper)
                                .overlay(Capsule().strokeBorder(
                                    Palette.hairline, lineWidth: Metrics.hairline))
                        )

                    Button {
                        runEdit()
                    } label: {
                        Text(editing ? "Working..." : "Go")
                            .font(.miraLabel)
                            .foregroundStyle(Palette.onInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Palette.ink))
                    }
                    .buttonStyle(.plain)
                    .disabled(editing || instruction.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("sticker.ai.run")

                    Button("Done") { onClose() }
                        .font(.miraLabel)
                        .foregroundStyle(Palette.ink)
                        .fixedSize()
                        .accessibilityIdentifier("sticker.done")
                }

                if let notice {
                    Text(notice)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var currentSticker: GeneratedSticker? {
        if case .sticker(let sticker) = editor.item(itemID)?.content { return sticker }
        return nil
    }

    /// Stylize -> cutout -> outline -> replace in place; the new version
    /// joins favorites. Nothing changes unless the whole pipeline succeeds.
    private func runEdit() {
        let words = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editing, !words.isEmpty, let sticker = currentSticker,
              let data = imageStore.data(forFileName: sticker.fileName) else {
            notice = "This sticker has no stored pixels to change."
            return
        }
        editing = true
        notice = nil
        Task {
            defer { editing = false }
            do {
                let styled = try await studio.stylize(image: data, instruction: words)
                let cut = try await studio.cutout(image: styled, target: nil)
                let outlined = try await studio.outline(image: cut)
                let fileName = try imageStore.save(outlined, id: UUID())
                let edited = GeneratedSticker(
                    prompt: sticker.prompt,
                    symbolName: sticker.symbolName,
                    fileName: fileName
                )
                editor.replaceSticker(itemID: itemID, with: edited)
                favoritesStore.add(edited)
                instruction = ""
                notice = "Done -- take a look. Undo brings the old one back."
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}
```

- [ ] **Step 5: Wire the state in CanvasScene.swift**

(a) After `@State private var editingImageItem: CanvasItem.ID?` (line 25):

```swift
    @State private var editingStickerItem: CanvasItem.ID?
```

(b) In the `CanvasBoardView(...)` init (line ~45), after the `onEditImage:` closure argument:

```swift
                onEditSticker: { id in
                    guard !mira.isWorking else { return }
                    cancelRecording()
                    cancelDictationIfNeeded()
                    editingStickerItem = id
                }
```

(c) In the bottom cluster (line ~141), add an `else if` between the photo panel and the recorder:

```swift
            if let editingImageItem {
                PhotoEditPanel(
                    editor: editor,
                    itemID: editingImageItem,
                    studio: imageStudio,
                    onClose: { self.editingImageItem = nil }
                )
                InputModeBar(active: .image, onSelect: handleTool)
            } else if let editingStickerItem {
                StickerEditPanel(
                    editor: editor,
                    itemID: editingStickerItem,
                    studio: imageStudio,
                    onClose: { self.editingStickerItem = nil }
                )
            } else {
                recorderCluster
            }
```

(d) In the `.onChange(of: editor.changeCount)` block (line ~81), after the editingImageItem check:

```swift
            if let id = editingStickerItem {
                if case .sticker = editor.item(id)?.content {} else {
                    editingStickerItem = nil
                }
            }
```

(e) In `handleTool` (line ~196), extend the panel-closing line:

```swift
        editingImageItem = nil
        editingStickerItem = nil
```

- [ ] **Step 6: Run the two UI tests on the shadow simulator**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcrun simctl bootstatus 35B7DA99-2D8B-4E9D-9848-FE17661F0B59 -b
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  -only-testing:MiraNoteUITests/StickerEditUITests 2>&1 | tail -5
```
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add App/Sources/Screens/Editor/StickerEditPanel.swift \
        App/Sources/Screens/Editor/CanvasBoardView.swift \
        App/Sources/Screens/Editor/CanvasScene.swift \
        App/UITests/StickerEditUITests.swift
git commit -m "feat: add the long-press edit sticker panel

Refs #21

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Gates, live film-strip, PR

**Files:**
- No new files (a throwaway live probe is written and deleted; never committed).

- [ ] **Step 1: swiftlint strict**

Run: `cd /Users/mengjia/MiraNote/miranote-ios && swiftlint --strict 2>&1 | tail -3`
Expected: `Found 0 violations` (fix and re-run if not; file/type/function caps are the usual suspects).

- [ ] **Step 2: Full Kit suite**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | tail -3`
Expected: 0 failures.

- [ ] **Step 3: Full app suites on the SHADOW simulator only**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  2>&1 | tail -5
```
Expected: TEST SUCCEEDED. Never point this at 6E165F5B-C411-40B4-A1A7-940E548D0D21 (the user's simulator).

- [ ] **Step 4: Live film-strip against :8002**

Verify backends are up (`curl -s localhost:8002/health`), install the branch build on the shadow simulator, and run one real pass: place a generated sticker, ask "make the sticker blue", screenshot the strip (working verb -> receipt -> restyled sticker with intact die-cut edge), long-press -> Edit sticker -> "give it a red scarf" -> screenshot. Any transparency/edge artifact here means the pipeline order (stylize before cutout) needs eyes before the PR. Delete any probe files afterward.

- [ ] **Step 5: Push and open the PR**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git push -u origin feat/sticker-edit
gh pr create --repo MiraNote-AI/miranote-ios \
  --title "feat(ios): edit placed stickers with words" \
  --body "$(cat <<'EOF'
Closes #21. Spec: docs/specs/2026-07-10-sticker-edit-design.md (in this PR).

## What

- Mira understands definite sticker asks ("make the sticker blue",
  Chinese equivalents): stylize -> cutout -> outline on :8002, replace
  in place, one undo, new version joins favorites.
- Target resolution mirrors photos (selected, else only, else clarify).
- Long-press on a sticker gains Edit sticker -> a one-field panel
  running the same pipeline.
- Fix: a sticker-flavored ask ("make the sticker warmer") no longer
  lands on the photo warm filter.

## Why this approach

In-place edit (not regenerate) and a full re-cut (not alpha reuse)
were decided with Meng in session -- the re-cut is the only variant
that survives shape-changing asks. Backend untouched.

## Not verified

- HUMAN: whether Nano Banana edits read as "the same sticker, changed"
  on real asks -- one live film-strip pass looked right; taste call is
  the reviewer's.
EOF
)"
```
Expected: PR URL printed; CI (checks + iOS suite) goes green. A human merges -- never self-merge.

---

## Iterations

(Ledger per run-loop: one line per act+verify cycle.)
