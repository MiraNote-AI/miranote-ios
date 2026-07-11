# Image-Text Intents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Words-about-pictures land as captions, pictures-from-words carry the page's words, generation uses the api's art command, and zero-photo clarifies stop lying.

**Architecture:** Four contained changes in the cue router and studio enum: an `.art` kind, a wantsWords guard ahead of the photo free edit plus widened captionCues, an illustrateText family checked before generation, and a question payload on clarifyPhoto. The placement pipeline is reused untouched.

**Tech Stack:** Swift, XCTest, swiftlint. Spec: docs/specs/2026-07-11-image-text-intents-design.md. Refs #26. Branch feat/image-text-intents. Backend already shipped (api#32).

## Global Constraints

- Org Rule 3: Chinese cues as unicode escapes in Swift source.
- swiftlint --strict 0; suites ONLY on shadow sim 35B7DA99-2D8B-4E9D-9848-FE17661F0B59.
- Copy strings exact: "No photo on this page yet -- add one first?", "More than one photo here -- tap the one you mean and ask again.", illustrateText prompt prefix "An illustration of: ".

---

### Task 1: The art kind, with a recording stub proving who sends what

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ImageStudio.swift` (enum, ~line 4-10)
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift` (generateChoices call site in performSlowImage)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraArtKindTests.swift` (create)

**Interfaces:**
- Produces: `GeneratedImageKind.art` (rawValue "art"). Task 3 sends it for illustrateText.

- [ ] **Step 1: Failing test**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraArtKindTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

/// Records the kind each generate call carries.
final class KindRecordingStudio: ImageStudioService, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [GeneratedImageKind] = []
    var kinds: [GeneratedImageKind] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        lock.lock(); recorded.append(kind); lock.unlock()
        return [Data("img-A".utf8), Data("img-B".utf8)]
    }
    func cutout(image: Data, target: String?) async throws -> Data { Data("cut".utf8) }
    func stylize(image: Data, instruction: String) async throws -> Data { Data("styled".utf8) }
    func outline(image: Data) async throws -> Data { Data("outlined".utf8) }
    func describe(image: Data) async throws -> String { "a recorded look" }
}

@MainActor
final class MiraArtKindTests: XCTestCase {
    func testPictureGenerationRequestsArt() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.generateImage(prompt: "draw a paper crane", sticker: false)
        _ = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        XCTAssertEqual(studio.kinds, [.art], "object art must not ride the background command")
    }

    func testStickerGenerationStillRequestsSticker() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.generateImage(prompt: "a cat sticker", sticker: true)
        _ = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        XCTAssertEqual(studio.kinds, [.sticker])
    }

    func testBackgroundAskStillRequestsBackground() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.setBackground(prompt: "a sunset background")
        _ = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        XCTAssertEqual(studio.kinds, [.background])
    }
}
```

- [ ] **Step 2: Run, expect compile failure** (`.art` missing)

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MiraArtKindTests 2>&1 | tail -3`

- [ ] **Step 3: Implement**

`ImageStudio.swift` enum gains:

```swift
    /// Standalone subject illustration (the api's art command).
    case art
```

and its doc comment on `.background` drops the "closest match" stand-in note:

```swift
    /// Full-bleed page backdrop art (the api's background command).
    case background
```

`MiraIntent+Image.swift`, in `performSlowImage`, the generateImage case sends art:

```swift
        case .generateImage(let prompt, let sticker):
            return try await generateChoices(
                imageStudio, kind: sticker ? .sticker : .art,
                prompt: prompt, placement: sticker ? .sticker : .picture)
```

- [ ] **Step 4: Green + full Kit**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | grep -E "Executed.*failures" | tail -1`
Expected: 190 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ImageStudio.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraArtKindTests.swift
git commit -m "feat: send object generation to the art command

Refs #26

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Words-wanting asks become captions; clarifyPhoto carries its question

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift` (captionCues ~line 130; clarifyPhoto case)
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift` (photoIntent; performSlowImage default)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraWordsAboutPicturesTests.swift` (create); Modify `MiraImageIntentTests.swift` (clarify binding)

**Interfaces:**
- Produces: `case clarifyPhoto(question: String)`; wantsWords guard. Task 3 must not reorder around them.

- [ ] **Step 1: Failing tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraWordsAboutPicturesTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraWordsAboutPicturesTests: XCTestCase {
    private func editorWithPhoto() -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addImages(
            [ImageRef(displayName: "sunset", fileName: "p.png")],
            around: CGPoint(x: 150, y: 100))
        return editor
    }

    func testMengsExactPhraseBecomesACaption() {
        // Device repro 2026-07-11: this restyled the photo.
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("Add a text to describe the picture", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testDescribeThePhotoBecomesACaption() {
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("describe the photo", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testChineseDescribeBecomesACaption() {
        let editor = editorWithPhoto()
        // "miaoshu yixia zhaopian" -- describe the photo.
        let intent = MiraIntent.classify(
            "\u{63CF}\u{8FF0}\u{4E00}\u{4E0B}\u{7167}\u{7247}", editor: editor)
        guard case .addCaption = intent else {
            return XCTFail("expected addCaption, got \(intent)")
        }
    }

    func testFreeEditStillWorksWithoutWordCues() {
        let editor = editorWithPhoto()
        let intent = MiraIntent.classify("make the photo feel like autumn", editor: editor)
        guard case .editPhoto = intent else {
            return XCTFail("expected editPhoto, got \(intent)")
        }
    }

    func testZeroPhotoFilterAskGetsTheHonestQuestion() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("make the photo black and white", editor: editor)
        guard case .clarifyPhoto(let question) = intent else {
            return XCTFail("expected clarifyPhoto, got \(intent)")
        }
        XCTAssertTrue(question.contains("No photo"), "zero photos must not say 'more than one'")
    }
}
```

In `MiraImageIntentTests.swift`, `testAmbiguousPhotoAsksToTap` binding becomes:

```swift
        guard case .clarifyPhoto(let question) = intent else {
            return XCTFail("expected clarifyPhoto, got \(intent)")
        }
        XCTAssertTrue(question.contains("tap the one you mean"))
```

- [ ] **Step 2: Run, expect failures** (payload missing; caption misses)

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter "MiraWordsAboutPicturesTests|MiraImageIntentTests" 2>&1 | tail -4`

- [ ] **Step 3: Implement**

`MiraIntent.swift`:

(a) `case clarifyPhoto` becomes `case clarifyPhoto(question: String)`.

(b) captionCues gain the describe forms:

```swift
        let captionCues = [
            "caption", "add a few words", "add words", "add text", "add a text",
            "write something", "write a few", "describe",
            "\u{914D}\u{6587}", "\u{52A0}\u{4E00}\u{6BB5}", "\u{5199}\u{4E00}\u{6BB5}",
            "\u{52A0}\u{6BB5}\u{6587}\u{5B57}", "\u{5199}\u{6BB5}",
            "\u{63CF}\u{8FF0}", "\u{5199}\u{51E0}\u{53E5}"
        ]
```

`MiraIntent+Image.swift`:

(c) In `photoIntent`, the free edit declines words-wanting asks:

```swift
        let wantsWords = ["describe", "add a text", "add text", "caption",
                          "write about", "in words",
                          "\u{63CF}\u{8FF0}", "\u{5199}\u{4E00}\u{6BB5}",
                          "\u{914D}\u{6587}", "\u{5199}\u{51E0}\u{53E5}"]
            .contains(where: lowered.contains)
        let freeEdit = mentionsPhoto && !wantsWords && Self.hasEditVerb(lowered)
```

(d) The two clarifyPhoto returns carry questions:

```swift
        case .none:
            // A photo-flavored ask with no photo on the page: only claim
            // it when the words really are about a photo.
            return (stickerCut || mentionsPhoto)
                ? .clarifyPhoto(question: "No photo on this page yet -- add one first?")
                : nil
        case .ambiguous:
            return .clarifyPhoto(
                question: "More than one photo here -- tap the one you mean and ask again.")
```

(e) `performSlowImage`'s default becomes an explicit clarify case (default now unreachable-but-total):

```swift
        case .clarifyPhoto(let question):
            throw MiraClarifyError(question: question, chips: [])
        default:
            throw MiraClarifyError(
                question: "More than one photo here -- tap the one you mean and ask again.",
                chips: []
            )
```

- [ ] **Step 4: Green + full Kit**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | grep -E "Executed.*failures" | tail -1`
Expected: 195 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraWordsAboutPicturesTests.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraImageIntentTests.swift
git commit -m "fix: route words-about-pictures asks to captions

Refs #26

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: illustrateText -- pictures from the page's words

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift` (case, verb, delegation)
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift` (family + order + perform)
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraIllustrateTextTests.swift` (create)

**Interfaces:**
- Consumes: `targetTextBlock(editor:)`, `generateChoices(_:kind:prompt:placement:)`, `.art`.
- Produces: `case illustrateText(prompt: String)`.

- [ ] **Step 1: Failing tests**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraIllustrateTextTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraIllustrateTextTests: XCTestCase {
    private func editorWithText(_ words: String = "a quiet morning by the sea") -> CanvasViewModel {
        let editor = CanvasViewModel(memory: Memory())
        _ = editor.addText(words, at: CGPoint(x: 150, y: 80))
        return editor
    }

    func testTurnThisTextIntoAPictureCarriesTheWords() {
        let editor = editorWithText()
        let intent = MiraIntent.classify("turn this text into a picture", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("a quiet morning by the sea"),
                      "the page's words ride the prompt, not the instruction")
    }

    func testChineseIntoPictureCarriesTheWords() {
        let editor = editorWithText()
        // "ba zhe duan wenzi hua cheng tu" -- draw this text as a picture.
        let intent = MiraIntent.classify(
            "\u{628A}\u{8FD9}\u{6BB5}\u{6587}\u{5B57}\u{753B}\u{6210}\u{56FE}", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("a quiet morning by the sea"))
    }

    func testNoTextClarifies() {
        let editor = CanvasViewModel(memory: Memory())
        let intent = MiraIntent.classify("turn this text into a picture", editor: editor)
        guard case .clarifyNoText = intent else {
            return XCTFail("expected clarifyNoText, got \(intent)")
        }
    }

    func testSelectedBlockWinsOverLongest() {
        let editor = editorWithText("the much much much longer block of words here")
        let short = editor.addText("tiny sea", at: CGPoint(x: 150, y: 260))
        editor.select(short)
        let intent = MiraIntent.classify("turn this text into a picture", editor: editor)
        guard case .illustrateText(let prompt) = intent else {
            return XCTFail("expected illustrateText, got \(intent)")
        }
        XCTAssertTrue(prompt.contains("tiny sea"))
        XCTAssertFalse(prompt.contains("longer block"))
    }

    func testPerformYieldsPictureChoicesViaArt() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.illustrateText(prompt: "An illustration of: tiny sea")
        let outcome = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        XCTAssertEqual(studio.kinds, [.art])
        guard case .imageChoices(let images, _, let placement) = outcome else {
            return XCTFail("expected imageChoices, got \(outcome)")
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(placement, .picture)
    }

    func testPlainDrawIsUntouched() {
        let editor = editorWithText()
        let intent = MiraIntent.classify("draw a paper crane", editor: editor)
        guard case .generateImage = intent else {
            return XCTFail("expected generateImage, got \(intent)")
        }
    }
}
```

- [ ] **Step 2: Run, expect compile failure**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test --filter MiraIllustrateTextTests 2>&1 | tail -3`

- [ ] **Step 3: Implement**

`MiraIntent.swift`: after `clearBackground`:

```swift
    case illustrateText(prompt: String)
```

verb (next to setBackground):

```swift
        case .illustrateText: return "Painting..."
```

perform delegation gains `.illustrateText` in the image group.

`MiraIntent+Image.swift`:

(a) isSlowImageWork gains `.illustrateText`.

(b) In `classifyImageOrStyle`, FIRST check (before generativeIntent):

```swift
        if let illustration = illustrateTextIntent(lowered, editor: editor) {
            return illustration
        }
```

(c) The family (near backgroundIntent):

```swift
    /// Pictures FROM the page's words ("turn this text into a picture",
    /// "\u{628A}\u{8FD9}\u{6BB5}\u{6587}\u{5B57}\u{753B}\u{6210}\u{56FE}").
    /// Checked before generation (the hua in hua-cheng-tu) and before the
    /// photo family (the word "picture").
    @MainActor
    private static func illustrateTextIntent(
        _ lowered: String, editor: CanvasViewModel
    ) -> MiraIntent? {
        let mentionsText = ["this text", "the text", "my text",
                            "\u{8FD9}\u{6BB5}\u{6587}\u{5B57}", "\u{8FD9}\u{6BB5}\u{8BDD}",
                            "\u{6587}\u{5B57}"]
            .contains(where: lowered.contains)
        let intoPicture = ["into a picture", "into an image", "as a picture",
                           "\u{753B}\u{6210}", "\u{53D8}\u{6210}\u{56FE}"]
            .contains(where: lowered.contains)
        guard mentionsText, intoPicture else { return nil }
        guard let (_, words) = targetTextBlock(editor: editor) else {
            return .clarifyNoText
        }
        return .illustrateText(prompt: "An illustration of: " + words)
    }
```

(d) performSlowImage gains (next to setBackground):

```swift
        case .illustrateText(let prompt):
            return try await generateChoices(
                imageStudio, kind: .art, prompt: prompt, placement: .picture)
```

- [ ] **Step 4: Green + full Kit**

Run: `cd /Users/mengjia/MiraNote/miranote-ios/MiraNoteKit && swift test 2>&1 | grep -E "Executed.*failures" | tail -1`
Expected: 201 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift \
        MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent+Image.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/MiraIllustrateTextTests.swift
git commit -m "feat: illustrate the page's words on request

Refs #26

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: UITests, gates, live film-strip, PR

**Files:**
- Test: `App/UITests/ImageTextUITests.swift` (create)

- [ ] **Step 1: UITests**

Create `App/UITests/ImageTextUITests.swift`:

```swift
import XCTest

/// Words-about-pictures and pictures-from-words (mock studio).
final class ImageTextUITests: XCTestCase {
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

    private func addSamplePhoto() {
        app.buttons["mode.image"].tap()
        let samples = app.buttons["image.library.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        samples.tap()
        let second = app.descendants(matching: .any)
            .matching(identifier: "element.image").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            .withOffset(CGVector(dx: 0, dy: 120)).tap()
    }

    func testDescribeAskAddsWordsNotARestyle() {
        startMemory()
        addSamplePhoto()
        ask("Add a text to describe the picture")
        XCTAssertTrue(app.staticTexts["Added a few words."].waitForExistence(timeout: 8),
                      "the caption receipt, not a restyle")
    }

    func testTextIntoPictureLandsAnImage() {
        startMemory()
        app.buttons["mode.text"].tap()
        let editorField = app.textViews["canvas.textEditor"]
        XCTAssertTrue(editorField.waitForExistence(timeout: 5))
        editorField.typeText("a quiet morning by the sea")
        ask("turn this text into a picture")

        let first = app.buttons["mira.imageChoice.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        XCTAssertTrue(app.staticTexts["mira.receipt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "element.image").firstMatch.exists,
            "the illustration landed")
    }
}
```

- [ ] **Step 2: xcodegen + run both on the shadow sim**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
xcodegen generate
xcodebuild test -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,id=35B7DA99-2D8B-4E9D-9848-FE17661F0B59' \
  -only-testing:MiraNoteUITests/ImageTextUITests 2>&1 | grep -E "Test Case '|TEST" | tail -5
```
Expected: both PASS (adjust the tap-into-text flow to the real editor ids if the first run reveals drift; canvas.textEditor is the shipped identifier).

- [ ] **Step 3: Gates**

lint from root (0), full Kit, full app suites on the shadow sim (SUCCEEDED).

- [ ] **Step 4: Live film-strip against :8002**

Throwaway probe, never committed: live launch; type a sentence; "turn this text into a picture" -> candidates within 150 s -> place -> screenshot (the illustration depicts the sentence, not the words "this text"); separately "draw a paper crane" -> place -> screenshot (a crane illustration, not wallpaper). Delete probe, xcodegen.

- [ ] **Step 5: Commit UITests, push, PR**

```bash
cd /Users/mengjia/MiraNote/miranote-ios
git add App/UITests/ImageTextUITests.swift
git commit -m "test: pin the two image-text flows end to end

Refs #26

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin feat/image-text-intents
gh pr create --repo MiraNote-AI/miranote-ios \
  --title "fix(ios): route image-text asks to the right abilities" \
  --body "$(cat <<'EOF'
Closes #26. Spec: docs/specs/2026-07-11-image-text-intents-design.md
(in this PR). Pairs with merged miranote-api#32.

## What

- Words-about-pictures asks (Meng's device repro "Add a text to
  describe the picture", "describe the photo", Chinese forms) now land
  as captions on the page instead of restyling the photo.
- "Turn this text into a picture" (EN/ZH) generates from the targeted
  text block's WORDS through the api's art command, landing like any
  picture.
- Object generation ("draw a paper crane") switches from the misused
  background command to art -- illustrations, not wallpaper.
- Zero-photo photo asks say "No photo on this page yet -- add one
  first?" instead of the lying "More than one photo here".

## Testing

- 14 new Kit tests incl. a kind-recording stub (art/sticker/background
  each verified) and the exact device phrase; full Kit suite green,
  lint 0, full app suites green on the shadow simulator.
- Live film-strip: crane illustration and a text-to-picture pass
  against real :8002.

## Not verified

- HUMAN: illustration taste across many prompts.
EOF
)"
```
Then watch CI to green; fresh-context review per maker-checker; a human merges.

## Iterations

(Ledger: one line per act+verify cycle.)
