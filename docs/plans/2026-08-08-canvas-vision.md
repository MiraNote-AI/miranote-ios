# Mira sees the canvas -- iOS implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Mira on the canvas a structured map of the page on every
turn, a rendered image she can ask to look at, and the ability to move,
resize, restyle and re-layer elements through one atomic change.

**Architecture:** A pure `PageMap` builder turns the editor's state into
numbered elements with boxes; `ElementChange` values come back and pass
three pure guards before a single `applyPageEdits` call mutates
`memory.items` behind one undo snapshot. The `.converse` branch of
`MiraIntent` is the only classifier path that changes. Rendering lives
in the App layer and reaches the coordinator through a closure, the same
shape as the existing `prepareTurn`.

**Tech Stack:** Swift 5.9+, SwiftUI, Observation, XCTest, URLSession.

Implements miranote-ios#41. Requires miranote-api#38 already merged and
running. Design: `docs/specs/2026-08-08-canvas-vision-design.md`.

## Global Constraints

- **No CJK or emoji in committed code.** Chinese trigger phrases stay
  on the backend, in `prompts/tool_descriptions.txt`. Any Chinese
  string that must appear in Swift is written with `\u{...}` escapes,
  as `MiraIntent.captionCues` already does.
- **The canvas is device-width.** `editor.canvasWidth` is the real
  board width (`CanvasBoardView.swift:113`). **Nothing in this feature
  may hardcode 360.** Every test that touches coordinates must use a
  width that is not 360, so a regression to the constant fails loudly.
- **One canvas change is one undo step.** The apply path takes exactly
  one `beginChange()` and then mutates `memory.items` directly. It must
  never call `setTextPointSize`, `setTextColorName`, `bringToFront` or
  `sendToBack`, each of which takes its own snapshot.
- **Point sizes clamp to 11-48.**
- **Build and test:**
  `cd MiraNoteKit && swift build && swift test`
  (`swift test` needs full Xcode; Command Line Tools ship no XCTest.)
- **Lint from the repo root, never from `MiraNoteKit/`** -- running it
  from the package directory reports about 35 phantom violations.

---

### Task 1: Build the page map

**Files:**
- Create: `MiraNoteKit/Sources/MiraNoteKit/PageMap.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/PageMapTests.swift`

**Interfaces:**
- Consumes: `Memory`, `CanvasItem`, `TextBlock`, `ImageRef`,
  `GeneratedSticker`, `SoundClip` from `Models.swift`.
- Produces:

```swift
public struct PageMap: Codable, Equatable, Sendable {
    public struct Element: Codable, Equatable, Sendable {
        public let handle: String
        public let kind: String        // text | photo | sticker | sound
        public let x, y, w, h: Double  // top-left box, canvas points
        public let says: String
        public let pointSize: Double?
        public let color: String?
        public let rotation: Double?
        public let treatment: String?
    }
    public let width: Double
    public let height: Double
    public let background: String
    public let palette: [String]
    public let elements: [Element]
    public let omitted: Int
}

public enum CanvasPalette {
    public static let names: [String]
}

extension PageMap {
    public static let maxElements = 24
    public static func build(
        from memory: Memory, canvasWidth: CGFloat
    ) -> (map: PageMap, handles: [String: CanvasItem.ID])
}
```

- [ ] **Step 1: Write the failing test**

Create `MiraNoteKit/Tests/MiraNoteKitTests/PageMapTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

final class PageMapTests: XCTestCase {
    /// Deliberately not 360: a hardcoded design width must fail here.
    private let width: CGFloat = 393

    private func text(_ body: String, y: CGFloat, size: CGFloat = 17) -> CanvasItem {
        CanvasItem(
            content: .text(TextBlock(text: body, pointSize: size)),
            position: CGPoint(x: 180, y: y),
            size: CGSize(width: 304, height: 44)
        )
    }

    func testMapReportsTheRealCanvasWidth() {
        let memory = Memory(items: [text("hello", y: 60)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertEqual(map.width, 393)
    }

    func testElementsAreOrderedTopToBottomNotByCreation() {
        let memory = Memory(items: [text("lower", y: 400), text("upper", y: 60)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertEqual(map.elements.map(\.says), ["upper", "lower"])
        XCTAssertEqual(map.elements.map(\.handle), ["t1", "t2"])
    }

    func testHandlesAreNumberedPerKind() {
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: "f", summary: "a bowl")),
            position: CGPoint(x: 180, y: 200),
            size: CGSize(width: 280, height: 200)
        )
        let memory = Memory(items: [text("title", y: 60), photo, text("body", y: 500)])
        let (map, handles) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertEqual(map.elements.map(\.handle), ["t1", "p1", "t2"])
        XCTAssertEqual(handles.count, 3)
        XCTAssertEqual(handles["p1"], photo.id)
    }

    func testBoxesAreTopLeftNotCentered() {
        // position is the CENTER; the map must emit the corner.
        let memory = Memory(items: [text("hello", y: 100)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        let element = map.elements[0]
        XCTAssertEqual(element.x, 180 - 304 / 2)
        XCTAssertEqual(element.y, 100 - 44 / 2)
        XCTAssertEqual(element.w, 304)
        XCTAssertEqual(element.h, 44)
    }

    func testDefaultStyleIsOmitted() {
        let memory = Memory(items: [text("hello", y: 60)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertNil(map.elements[0].color)
        XCTAssertNil(map.elements[0].rotation)
        XCTAssertNil(map.elements[0].treatment)
        XCTAssertEqual(map.elements[0].pointSize, 17)
    }

    func testNonDefaultStyleIsCarried() {
        var item = text("hello", y: 60)
        item.rotation = 8
        item.content = .text(TextBlock(text: "hello", pointSize: 30, colorName: "forest"))
        let (map, _) = PageMap.build(from: Memory(items: [item]), canvasWidth: width)
        XCTAssertEqual(map.elements[0].color, "forest")
        XCTAssertEqual(map.elements[0].rotation, 8)
    }

    func testPhotoWithoutVisionSaysSo() {
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: "f", summary: "")),
            position: CGPoint(x: 180, y: 200)
        )
        let (map, _) = PageMap.build(from: Memory(items: [photo]), canvasWidth: width)
        XCTAssertTrue(map.elements[0].says.contains("has not looked at"))
    }

    func testCapAt24AndStateTheRemainder() {
        let items = (0..<30).map { text("block \($0)", y: CGFloat($0) * 50) }
        let (map, handles) = PageMap.build(from: Memory(items: items), canvasWidth: width)
        XCTAssertEqual(map.elements.count, PageMap.maxElements)
        XCTAssertEqual(map.omitted, 6)
        XCTAssertEqual(handles.count, PageMap.maxElements)
    }

    func testPaletteIsStatedSoTheModelNeedNotGuess() {
        let (map, _) = PageMap.build(from: Memory(items: []), canvasWidth: width)
        XCTAssertEqual(map.palette, CanvasPalette.names)
        XCTAssertTrue(map.palette.contains("ink"))
    }

    func testHeightCoversTheContent() {
        let memory = Memory(items: [text("hello", y: 900)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertGreaterThan(map.height, 900)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd MiraNoteKit && swift test --filter PageMapTests`
Expected: FAIL to compile, `cannot find 'PageMap' in scope`

- [ ] **Step 3: Write the implementation**

Create `MiraNoteKit/Sources/MiraNoteKit/PageMap.swift`:

```swift
import CoreGraphics
import Foundation

/// The palette names a canvas text block may persist in
/// `TextBlock.colorName`. The App layer resolves them to colors
/// (`Palette.color(named:)`); this list is the contract between the
/// two, and is also what Mira is offered to choose from.
public enum CanvasPalette {
    public static let names = ["ink", "onInk", "forest", "taupe", "tan", "sage"]
}

/// The page as Mira reads it: every element numbered, boxed, and
/// described. This is the source of truth for WHERE things are; the
/// rendered image (look_at_page) only carries how the page LOOKS.
public struct PageMap: Codable, Equatable, Sendable {
    public struct Element: Codable, Equatable, Sendable {
        public let handle: String
        public let kind: String
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double
        public let says: String
        public let pointSize: Double?
        public let color: String?
        public let rotation: Double?
        public let treatment: String?

        enum CodingKeys: String, CodingKey {
            case handle, kind, x, y, w, h, says
            case pointSize = "point_size"
            case color, rotation, treatment
        }
    }

    public let width: Double
    public let height: Double
    public let background: String
    public let palette: [String]
    public let elements: [Element]
    public let omitted: Int
}

public extension PageMap {
    /// Past this the block stops being readable and starts being a
    /// token bill. The remainder is stated, never silently dropped.
    static let maxElements = 24

    /// Returns the map plus the handle -> item id table. The table
    /// stays on device: handles are per-turn, ids are forever.
    static func build(
        from memory: Memory, canvasWidth: CGFloat
    ) -> (map: PageMap, handles: [String: CanvasItem.ID]) {
        let ordered = memory.items.sorted {
            $0.position.y - $0.size.height / 2 < $1.position.y - $1.size.height / 2
        }
        var counters: [String: Int] = [:]
        var handles: [String: CanvasItem.ID] = [:]
        var elements: [Element] = []

        for item in ordered.prefix(maxElements) {
            let kind = Self.kind(of: item)
            let prefix = Self.prefix(for: kind)
            let next = (counters[prefix] ?? 0) + 1
            counters[prefix] = next
            let handle = "\(prefix)\(next)"
            handles[handle] = item.id
            elements.append(Element(
                handle: handle,
                kind: kind,
                x: Double(item.position.x - item.size.width / 2),
                y: Double(item.position.y - item.size.height / 2),
                w: Double(item.size.width),
                h: Double(item.size.height),
                says: Self.says(of: item),
                pointSize: Self.pointSize(of: item),
                color: Self.color(of: item),
                rotation: item.rotation == 0 ? nil : item.rotation,
                treatment: Self.treatment(of: item)
            ))
        }

        let bottom = memory.items
            .map { $0.position.y + $0.size.height / 2 }
            .max() ?? 0
        let map = PageMap(
            width: Double(canvasWidth),
            height: Double(max(620, bottom + 120)),
            background: memory.backgroundFileName.isEmpty
                ? "default gradient" : "a picked backdrop image",
            palette: CanvasPalette.names,
            elements: elements,
            omitted: max(0, memory.items.count - elements.count)
        )
        return (map, handles)
    }

    private static func kind(of item: CanvasItem) -> String {
        switch item.content {
        case .text: return "text"
        case .image: return "photo"
        case .sticker: return "sticker"
        case .sound: return "sound"
        }
    }

    private static func prefix(for kind: String) -> String {
        switch kind {
        case "text": return "t"
        case "photo": return "p"
        case "sticker": return "s"
        default: return "a"
        }
    }

    private static func says(of item: CanvasItem) -> String {
        switch item.content {
        case .text(let block):
            return block.text
        case .image(let ref):
            // Same honesty as the flat note form: a file name would
            // send the model chasing bookshelves.
            return ref.summary.isEmpty
                ? "a photo Mira has not looked at yet" : ref.summary
        case .sticker(let sticker):
            return sticker.prompt
        case .sound(let clip):
            return clip.note
        }
    }

    private static func pointSize(of item: CanvasItem) -> Double? {
        guard case .text(let block) = item.content else { return nil }
        return Double(block.pointSize)
    }

    private static func color(of item: CanvasItem) -> String? {
        guard case .text(let block) = item.content,
              block.colorName != "ink", !block.colorName.isEmpty else { return nil }
        return block.colorName
    }

    private static func treatment(of item: CanvasItem) -> String? {
        guard case .image(let ref) = item.content else { return nil }
        let marks = [ref.filterName, ref.frameName].filter { !$0.isEmpty }
        return marks.isEmpty ? nil : marks.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd MiraNoteKit && swift test --filter PageMapTests`
Expected: PASS, 10 tests

- [ ] **Step 5: Commit**

```bash
git add MiraNoteKit/Sources/MiraNoteKit/PageMap.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/PageMapTests.swift
git commit -m "feat(ios): describe the canvas page as a numbered element map

Refs #41"
```

---

### Task 2: Guard the changes coming back

**Files:**
- Create: `MiraNoteKit/Sources/MiraNoteKit/ElementChange.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/ElementChangeTests.swift`

**Interfaces:**
- Consumes: `PageMap`, `CanvasPalette` (Task 1).
- Produces:

```swift
public struct ElementChange: Codable, Equatable, Sendable {
    public enum Layer: String, Codable, Sendable { case front, back }
    public let handle: String
    public var x, y, w, h: Double?
    public var pointSize: Double?
    public var color: String?
    public var layer: Layer?
}

public struct ResolvedChange: Equatable, Sendable {
    public let id: CanvasItem.ID
    public var x, y, w, h: Double?
    public var pointSize: CGFloat?
    public var colorName: String?
    public var layer: ElementChange.Layer?
}

public enum PageEditGuard {
    public static let pointSizeRange: ClosedRange<CGFloat> = 11...48
    public static func resolve(
        _ changes: [ElementChange],
        handles: [String: CanvasItem.ID],
        canvasWidth: CGFloat
    ) -> [ResolvedChange]
    public static func merge(_ sets: [[ElementChange]]) -> [ElementChange]
}
```

- [ ] **Step 1: Write the failing test**

Create `MiraNoteKit/Tests/MiraNoteKitTests/ElementChangeTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

final class ElementChangeTests: XCTestCase {
    private let width: CGFloat = 393   // never 360
    private let id = UUID()
    private var handles: [String: CanvasItem.ID] { ["t1": id] }

    private func change(
        _ handle: String = "t1", x: Double? = nil, y: Double? = nil,
        w: Double? = nil, h: Double? = nil, pointSize: Double? = nil,
        color: String? = nil, layer: ElementChange.Layer? = nil
    ) -> ElementChange {
        ElementChange(handle: handle, x: x, y: y, w: w, h: h,
                      pointSize: pointSize, color: color, layer: layer)
    }

    func testKnownHandleResolvesToItsItemID() {
        let resolved = PageEditGuard.resolve([change(x: 40)], handles: handles, canvasWidth: width)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].id, id)
        XCTAssertEqual(resolved[0].x, 40)
    }

    func testInventedHandleIsDropped() {
        let resolved = PageEditGuard.resolve([change("t9", x: 40)], handles: handles, canvasWidth: width)
        XCTAssertTrue(resolved.isEmpty)
    }

    func testUnknownColorIsDroppedButTheRestOfTheEntrySurvives() {
        let resolved = PageEditGuard.resolve(
            [change(x: 40, color: "warm beige")], handles: handles, canvasWidth: width
        )
        XCTAssertEqual(resolved.count, 1)
        XCTAssertNil(resolved[0].colorName)
        XCTAssertEqual(resolved[0].x, 40)
    }

    func testKnownColorSurvives() {
        let resolved = PageEditGuard.resolve(
            [change(color: "forest")], handles: handles, canvasWidth: width
        )
        XCTAssertEqual(resolved[0].colorName, "forest")
    }

    func testCoordinatesClampToTheRealCanvasWidth() {
        // 380 is inside a 393 canvas and outside a 360 one: a
        // hardcoded 360 fails this test.
        let resolved = PageEditGuard.resolve(
            [change(x: 380), change(x: -20)] .map { $0 },
            handles: handles, canvasWidth: width
        )
        XCTAssertEqual(resolved[0].x, 380)
        let negative = PageEditGuard.resolve([change(x: -20)], handles: handles, canvasWidth: width)
        XCTAssertEqual(negative[0].x, 0)
    }

    func testCoordinatesBeyondTheCanvasAreClampedIn() {
        let resolved = PageEditGuard.resolve([change(x: 900)], handles: handles, canvasWidth: width)
        XCTAssertLessThanOrEqual(resolved[0].x ?? 0, 393)
    }

    func testNegativeYIsClampedButLargeYIsAllowed() {
        let up = PageEditGuard.resolve([change(y: -50)], handles: handles, canvasWidth: width)
        XCTAssertEqual(up[0].y, 0)
        let down = PageEditGuard.resolve([change(y: 5000)], handles: handles, canvasWidth: width)
        XCTAssertEqual(down[0].y, 5000)
    }

    func testPointSizeClampsTo11Through48() {
        let small = PageEditGuard.resolve([change(pointSize: 4)], handles: handles, canvasWidth: width)
        XCTAssertEqual(small[0].pointSize, 11)
        let large = PageEditGuard.resolve([change(pointSize: 900)], handles: handles, canvasWidth: width)
        XCTAssertEqual(large[0].pointSize, 48)
    }

    func testMergeLetsLaterCallsWinFieldByField() {
        let merged = PageEditGuard.merge([
            [change(x: 10, y: 10)],
            [change(x: 99)],
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].x, 99)
        XCTAssertEqual(merged[0].y, 10)
    }

    func testMergeKeepsDistinctHandlesSeparate() {
        let merged = PageEditGuard.merge([[change("t1", x: 1)], [change("p1", x: 2)]])
        XCTAssertEqual(merged.count, 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd MiraNoteKit && swift test --filter ElementChangeTests`
Expected: FAIL to compile, `cannot find 'ElementChange' in scope`

- [ ] **Step 3: Write the implementation**

Create `MiraNoteKit/Sources/MiraNoteKit/ElementChange.swift`:

```swift
import CoreGraphics
import Foundation

/// One element's worth of change, as Mira asked for it. Every field is
/// optional: only what changes is sent.
public struct ElementChange: Codable, Equatable, Sendable {
    public enum Layer: String, Codable, Sendable {
        case front, back
    }

    public let handle: String
    public var x: Double?
    public var y: Double?
    public var w: Double?
    public var h: Double?
    public var pointSize: Double?
    public var color: String?
    public var layer: Layer?

    enum CodingKeys: String, CodingKey {
        case handle = "id"
        case x, y, w, h, color, layer
        case pointSize = "size"
    }

    public init(
        handle: String, x: Double? = nil, y: Double? = nil,
        w: Double? = nil, h: Double? = nil, pointSize: Double? = nil,
        color: String? = nil, layer: Layer? = nil
    ) {
        self.handle = handle
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.pointSize = pointSize
        self.color = color
        self.layer = layer
    }
}

/// A change that survived the guards, addressed at a real item.
public struct ResolvedChange: Equatable, Sendable {
    public let id: CanvasItem.ID
    public var x: Double?
    public var y: Double?
    public var w: Double?
    public var h: Double?
    public var pointSize: CGFloat?
    public var colorName: String?
    public var layer: ElementChange.Layer?
}

/// What stands between a language model's arithmetic and the user's
/// page. Pure functions, no editor state.
public enum PageEditGuard {
    public static let pointSizeRange: ClosedRange<CGFloat> = 11...48

    /// Later calls win field by field, so a model that corrects itself
    /// mid-turn lands the correction instead of two receipts.
    public static func merge(_ sets: [[ElementChange]]) -> [ElementChange] {
        var order: [String] = []
        var merged: [String: ElementChange] = [:]
        for set in sets {
            for change in set {
                guard var existing = merged[change.handle] else {
                    order.append(change.handle)
                    merged[change.handle] = change
                    continue
                }
                if let value = change.x { existing.x = value }
                if let value = change.y { existing.y = value }
                if let value = change.w { existing.w = value }
                if let value = change.h { existing.h = value }
                if let value = change.pointSize { existing.pointSize = value }
                if let value = change.color { existing.color = value }
                if let value = change.layer { existing.layer = value }
                merged[change.handle] = existing
            }
        }
        return order.compactMap { merged[$0] }
    }

    /// Drop what cannot be honoured, clamp what can. An entry whose
    /// handle names nothing is dropped whole; a bad colour only costs
    /// its own field.
    public static func resolve(
        _ changes: [ElementChange],
        handles: [String: CanvasItem.ID],
        canvasWidth: CGFloat
    ) -> [ResolvedChange] {
        changes.compactMap { change in
            guard let id = handles[change.handle] else { return nil }
            let width = Double(max(1, canvasWidth))
            return ResolvedChange(
                id: id,
                x: change.x.map { min(max(0, $0), width) },
                // The canvas scrolls downward without limit, so only
                // the top edge is a wall.
                y: change.y.map { max(0, $0) },
                w: change.w.map { min(max(1, $0), width) },
                h: change.h.map { max(1, $0) },
                pointSize: change.pointSize.map {
                    min(max(Self.pointSizeRange.lowerBound, CGFloat($0)),
                        Self.pointSizeRange.upperBound)
                },
                colorName: change.color.flatMap {
                    CanvasPalette.names.contains($0) ? $0 : nil
                },
                layer: change.layer
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd MiraNoteKit && swift test --filter ElementChangeTests`
Expected: PASS, 10 tests

- [ ] **Step 5: Commit**

```bash
git add MiraNoteKit/Sources/MiraNoteKit/ElementChange.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/ElementChangeTests.swift
git commit -m "feat(ios): validate and clamp Mira's page edits before applying

Refs #41"
```

---

### Task 3: Apply the edits as one change

**Files:**
- Create: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel+PageEdits.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/PageEditApplyTests.swift`

**Interfaces:**
- Consumes: `ResolvedChange` (Task 2), `Memory.estimatedTextHeight`
  (`StarterDraft.swift:116`).
- Produces:
  `CanvasViewModel.applyPageEdits(_ changes: [ResolvedChange]) -> Bool`
  -- returns whether anything landed, takes exactly one undo snapshot.

**This is the task the whole feature's honesty rests on.**
`setTextPointSize` (CanvasViewModel.swift:215), `setTextColorName`
(:223), `bringToFront` (:314) and `sendToBack` (:320) each call
`beginChange()` themselves, and `revert()` pops exactly one snapshot.
Route through them and a five-element change reverts one fifth of the
way, while the receipt promises the whole thing. Mutate
`memory.items` directly instead.

- [ ] **Step 1: Write the failing test**

Create `MiraNoteKit/Tests/MiraNoteKitTests/PageEditApplyTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class PageEditApplyTests: XCTestCase {
    private func editor(_ items: [CanvasItem]) -> CanvasViewModel {
        let model = CanvasViewModel(memory: Memory(items: items))
        model.canvasWidth = 393
        return model
    }

    private func textItem(
        _ body: String = "hello", y: CGFloat = 100, size: CGFloat = 17
    ) -> CanvasItem {
        CanvasItem(
            content: .text(TextBlock(text: body, pointSize: size)),
            position: CGPoint(x: 180, y: y),
            size: CGSize(width: 304, height: 44)
        )
    }

    func testAMixedChangeSetIsExactlyOneUndoStep() {
        let a = textItem("one", y: 100)
        let b = textItem("two", y: 300)
        let model = editor([a, b])
        let before = model.currentSnapshotItemsForTesting

        let landed = model.applyPageEdits([
            ResolvedChange(id: a.id, x: 20, y: 20, pointSize: 34, colorName: "forest", layer: .front),
            ResolvedChange(id: b.id, x: 20, y: 400, colorName: "sage", layer: .back),
        ])

        XCTAssertTrue(landed)
        model.undo()
        XCTAssertEqual(model.items.count, before.count)
        XCTAssertEqual(model.item(a.id)?.position, a.position)
        XCTAssertEqual(model.item(b.id)?.position, b.position)
        XCTAssertFalse(model.canUndo, "one change must leave exactly one snapshot")
    }

    func testPositionsAreTopLeftAndConvertBackToCenters() {
        let item = textItem()
        let model = editor([item])
        _ = model.applyPageEdits([ResolvedChange(id: item.id, x: 40, y: 60)])
        let moved = model.item(item.id)!
        XCTAssertEqual(moved.position.x, 40 + moved.size.width / 2)
        XCTAssertEqual(moved.position.y, 60 + moved.size.height / 2)
    }

    func testRaisingThePointSizeGrowsTheBoxBeforePositionsLand() {
        let item = textItem("a reasonably long line of text that wraps", y: 100, size: 15)
        let model = editor([item])
        let grown = Memory.estimatedTextHeight(
            "a reasonably long line of text that wraps", pointSize: 40, width: 304
        )
        _ = model.applyPageEdits([ResolvedChange(id: item.id, y: 200, pointSize: 40)])
        let after = model.item(item.id)!
        XCTAssertEqual(after.size.height, grown, accuracy: 0.5)
        // The requested top edge still wins after the re-measure.
        XCTAssertEqual(after.position.y - after.size.height / 2, 200, accuracy: 0.5)
    }

    func testLayerFrontAndBackRestackWithoutExtraSnapshots() {
        let a = textItem("one", y: 100)
        let b = textItem("two", y: 300)
        let model = editor([a, b])
        _ = model.applyPageEdits([ResolvedChange(id: a.id, layer: .front)])
        XCTAssertGreaterThan(model.item(a.id)!.zIndex, model.item(b.id)!.zIndex)
        model.undo()
        XCTAssertFalse(model.canUndo)
    }

    func testAnEmptyChangeSetTouchesNothing() {
        let model = editor([textItem()])
        XCTAssertFalse(model.applyPageEdits([]))
        XCTAssertFalse(model.canUndo)
    }

    func testChangesNamingMissingItemsTouchNothing() {
        let model = editor([textItem()])
        XCTAssertFalse(model.applyPageEdits([ResolvedChange(id: UUID(), x: 10)]))
        XCTAssertFalse(model.canUndo)
    }

    func testPointSizeOnANonTextElementIsIgnoredNotCrashing() {
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: "f")),
            position: CGPoint(x: 180, y: 100)
        )
        let model = editor([photo])
        XCTAssertTrue(model.applyPageEdits([ResolvedChange(id: photo.id, w: 200, pointSize: 40)]))
        XCTAssertEqual(model.item(photo.id)?.size.width, 200)
    }
}
```

Add the test-only accessor this file uses. In
`CanvasViewModel+PageEdits.swift`:

```swift
extension CanvasViewModel {
    /// Test seam: the item list as it stands, for before/after compares.
    var currentSnapshotItemsForTesting: [CanvasItem] { memory.items }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd MiraNoteKit && swift test --filter PageEditApplyTests`
Expected: FAIL to compile, `value of type 'CanvasViewModel' has no member 'applyPageEdits'`

- [ ] **Step 3: Write the implementation**

Create `MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel+PageEdits.swift`:

```swift
import CoreGraphics
import Foundation

public extension CanvasViewModel {
    /// Test seam: the item list as it stands, for before/after compares.
    var currentSnapshotItemsForTesting: [CanvasItem] { memory.items }

    /// Apply one turn's worth of Mira edits as a single change.
    ///
    /// Takes exactly one snapshot and then mutates `memory.items`
    /// directly. It deliberately does NOT call `setTextPointSize`,
    /// `setTextColorName`, `bringToFront` or `sendToBack`: each of
    /// those snapshots itself, and `revert()` pops only one, so
    /// routing through them would leave Revert undoing a fraction of
    /// what the receipt claims.
    ///
    /// Order matters. Point sizes land first and the text box is
    /// re-measured before positions are applied, because Mira computed
    /// its coordinates against the heights it was shown -- changing a
    /// size first would silently invalidate every position below it.
    ///
    /// Returns false when nothing landed, so the caller can show a
    /// clarify card instead of a receipt for a change that never was.
    @discardableResult
    func applyPageEdits(_ changes: [ResolvedChange]) -> Bool {
        let live = changes.filter { index(of: $0.id) != nil }
        guard !live.isEmpty else { return false }

        beginChange()

        // 1. Style, and 2. re-measure, in one pass per element.
        for change in live {
            guard let itemIndex = index(of: change.id) else { continue }
            guard case .text(var block) = memory.items[itemIndex].content else { continue }
            var touched = false
            if let pointSize = change.pointSize {
                block.pointSize = pointSize
                touched = true
            }
            if let colorName = change.colorName {
                block.colorName = colorName
                touched = true
            }
            guard touched else { continue }
            memory.items[itemIndex].content = .text(block)
            if change.pointSize != nil {
                let measured = Memory.estimatedTextHeight(
                    block.text,
                    pointSize: block.pointSize,
                    width: memory.items[itemIndex].size.width
                )
                let old = memory.items[itemIndex].size.height
                memory.items[itemIndex].size.height = max(36, measured)
                memory.items[itemIndex].position.y += (max(36, measured) - old) / 2
            }
        }

        // 3. Geometry and stacking, against boxes that are now honest.
        for change in live {
            guard let itemIndex = index(of: change.id) else { continue }
            if let w = change.w {
                memory.items[itemIndex].size.width = max(44, CGFloat(w))
            }
            if let h = change.h {
                memory.items[itemIndex].size.height = max(36, CGFloat(h))
            }
            let size = memory.items[itemIndex].size
            if let x = change.x {
                memory.items[itemIndex].position.x = CGFloat(x) + size.width / 2
            }
            if let y = change.y {
                memory.items[itemIndex].position.y = CGFloat(y) + size.height / 2
            }
            switch change.layer {
            case .front: memory.items[itemIndex].zIndex = topZ + 1
            case .back: memory.items[itemIndex].zIndex = bottomZ - 1
            case nil: break
            }
        }
        return true
    }
}
```

If `topZ`, `bottomZ` or `index(of:)` are not visible from an
extension in a separate file, widen them from `private` to internal in
`CanvasViewModel.swift` -- do not duplicate the logic.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd MiraNoteKit && swift test --filter PageEditApplyTests`
Expected: PASS, 7 tests

- [ ] **Step 5: Run the whole suite -- nothing else may regress**

Run: `cd MiraNoteKit && swift test`
Expected: PASS, all pre-existing tests included

- [ ] **Step 6: Commit**

```bash
git add MiraNoteKit/Sources/MiraNoteKit/ViewModels/CanvasViewModel+PageEdits.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/PageEditApplyTests.swift
git commit -m "feat(ios): apply a turn of page edits as one undoable change

Refs #41"
```

---

### Task 4: Carry the page over the wire

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/Chat.swift:40-117`
- Modify: `MiraNoteKit/Sources/MiraNoteKit/Networking/LiveChatService.swift`
- Modify: `MiraNoteKit/Tests/MiraNoteKitTests/MiraScriptedDoubles.swift`
- Test: append to
  `MiraNoteKit/Tests/MiraNoteKitTests/Networking/LiveChatServiceTests.swift`
  (it already has the `service()` and `sentBody(_:)` helpers and a
  `tearDown` that clears the stub -- do not start a second file)

**Interfaces:**
- Consumes: `PageMap` (Task 1), `ElementChange` (Task 2).
- Produces:

```swift
public struct PageContext: Sendable {
    public let map: PageMap
    public let image: Data?
}

public enum BackgroundRequest: Equatable, Sendable {
    case set(prompt: String)
    case clear
}

// ChatReply gains:
public let pageEdits: [ElementChange]
public let backgroundRequest: BackgroundRequest?

// ChatService gains a page parameter, defaulted so the chat screen
// and every existing call site keep compiling unchanged:
func reply(
    to message: String, sessionID: String?,
    notes: [ChatNote], page: PageContext?
) async throws -> ChatReply
```

- [ ] **Step 1: Write the failing test**

Append to
`MiraNoteKit/Tests/MiraNoteKitTests/Networking/LiveChatServiceTests.swift`,
reusing its existing `service()` and `sentBody(_:)` helpers,
`StubURLProtocol.makeSession()`, and `request.capturedBody`:

```swift
    private var canvasMap: PageMap {
        PageMap.build(from: Memory(items: []), canvasWidth: 393).map
    }

    private func canned(_ json: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
    }

    func testCanvasTurnSendsThePageAndItsImage() async throws {
        var sent: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            sent = self.sentBody(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"session_id":"s","reply":"ok","tool_trace":[]}"#.utf8))
        }
        _ = try await service().reply(
            to: "move the title up", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: Data([0xFF, 0xD8]))
        )
        let page = sent["page"] as? [String: Any]
        XCTAssertEqual(page?["width"] as? Double, 393)
        XCTAssertNotNil(page?["image"] as? String, "the JPEG rides along base64-encoded")
        XCTAssertNotNil(page?["palette"], "the model must be told which colors exist")
    }

    func testChatScreenTurnSendsNoPage() async throws {
        var sent: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            sent = self.sentBody(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"session_id":"s","reply":"ok","tool_trace":[]}"#.utf8))
        }
        _ = try await service().reply(to: "hello", sessionID: nil, notes: [])
        XCTAssertNil(sent["page"])
    }

    func testEditPageCallsAreReadOutOfTheToolTrace() async throws {
        canned("""
        {"session_id":"s","reply":"Moved it up.","tool_trace":[
          {"name":"edit_page","args":{"changes":[
            {"id":"t1","x":28,"y":24,"size":34,"color":"forest","layer":"front"}]}}]}
        """)
        let reply = try await service().reply(
            to: "move it", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.pageEdits.count, 1)
        XCTAssertEqual(reply.pageEdits[0].handle, "t1")
        XCTAssertEqual(reply.pageEdits[0].pointSize, 34)
        XCTAssertEqual(reply.pageEdits[0].layer, .front)
    }

    func testSeveralEditPageCallsMergeWithTheLaterOneWinning() async throws {
        canned("""
        {"session_id":"s","reply":"ok","tool_trace":[
          {"name":"edit_page","args":{"changes":[{"id":"t1","x":10,"y":10}]}},
          {"name":"edit_page","args":{"changes":[{"id":"t1","x":99}]}}]}
        """)
        let reply = try await service().reply(
            to: "move it", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.pageEdits.count, 1)
        XCTAssertEqual(reply.pageEdits[0].x, 99)
        XCTAssertEqual(reply.pageEdits[0].y, 10)
    }

    func testBackgroundRequestsAreReadOutOfTheToolTrace() async throws {
        canned("""
        {"session_id":"s","reply":"Painting.","tool_trace":[
          {"name":"set_background","args":{"prompt":"a quiet dusk sky"}}]}
        """)
        let reply = try await service().reply(
            to: "change the background", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertEqual(reply.backgroundRequest, .set(prompt: "a quiet dusk sky"))
    }

    func testUnknownToolCallsAreIgnored() async throws {
        canned("""
        {"session_id":"s","reply":"ok","tool_trace":[{"name":"look_at_page","args":{}}]}
        """)
        let reply = try await service().reply(
            to: "how does it look", sessionID: nil, notes: [],
            page: PageContext(map: canvasMap, image: nil)
        )
        XCTAssertTrue(reply.pageEdits.isEmpty)
        XCTAssertNil(reply.backgroundRequest)
    }
```

The existing `create_note` test in that file must keep passing
untouched -- if widening `TraceEntry` breaks it, the lenient decoding
was lost.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd MiraNoteKit && swift test --filter LiveChatServiceCanvasTests`
Expected: FAIL to compile, `cannot find 'PageContext' in scope`

- [ ] **Step 3: Extend the chat types**

In `Chat.swift`, add above `ChatReply`:

```swift
/// The page the user is editing right now, sent with a canvas turn.
/// `image` is a JPEG of the page as they see it -- it rides along on
/// every canvas turn but is only spent if Mira calls look_at_page.
public struct PageContext: Sendable {
    public let map: PageMap
    public let image: Data?

    public init(map: PageMap, image: Data?) {
        self.map = map
        self.image = image
    }
}

/// Slow image work Mira asked the app to run. The server does none of
/// it; it only records the request.
public enum BackgroundRequest: Equatable, Sendable {
    case set(prompt: String)
    case clear
}
```

Extend `ChatReply` with two stored properties and default them in the
initializer so existing construction sites keep compiling:

```swift
public let pageEdits: [ElementChange]
public let backgroundRequest: BackgroundRequest?

public init(
    text: String, sessionID: String?, pageDraft: ChatPageDraft? = nil,
    pageEdits: [ElementChange] = [], backgroundRequest: BackgroundRequest? = nil
) {
    self.text = text
    self.sessionID = sessionID
    self.pageDraft = pageDraft
    self.pageEdits = pageEdits
    self.backgroundRequest = backgroundRequest
}
```

Widen the protocol and keep the old shapes as defaults:

```swift
public protocol ChatService: Sendable {
    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply
}

public extension ChatService {
    func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        try await reply(to: message, sessionID: sessionID, notes: notes, page: nil)
    }

    func reply(to message: String, sessionID: String?) async throws -> ChatReply {
        try await reply(to: message, sessionID: sessionID, notes: [], page: nil)
    }
}
```

Update `MockChatService.reply` to the four-argument signature. Give it
one canned canvas behaviour so previews and snapshot QA exercise the
apply path with no network:

```swift
public func reply(
    to message: String, sessionID: String?,
    notes: [ChatNote], page: PageContext?
) async throws -> ChatReply {
    try await Task.sleep(for: .milliseconds(500))
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if let page, let first = page.map.elements.first,
       trimmed.lowercased().contains("move") || trimmed.lowercased().contains("tidy") {
        return ChatReply(
            text: "Moved it up for you.",
            sessionID: sessionID ?? "mock-session",
            pageEdits: [ElementChange(handle: first.handle, x: 28, y: 24)]
        )
    }
    // ... existing branches unchanged ...
}
```

- [ ] **Step 4: Wire the live service**

In `LiveChatService.swift`, extend `Request`:

```swift
private struct Request: Encodable {
    let sessionID: String?
    let message: String
    let notes: [ChatNote]
    let page: PageBody?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case message, notes, page
    }
}

/// The map plus the base64 JPEG, in the shape the backend's PageIn
/// expects.
private struct PageBody: Encodable {
    let width: Double
    let height: Double
    let background: String
    let palette: [String]
    let elements: [PageMap.Element]
    let omitted: Int
    let image: String?

    init(_ context: PageContext) {
        width = context.map.width
        height = context.map.height
        background = context.map.background
        palette = context.map.palette
        elements = context.map.elements
        omitted = context.map.omitted
        image = context.image?.base64EncodedString()
    }
}
```

Widen `TraceEntry` so it can carry page-edit and background arguments
alongside the draft ones it already decodes leniently:

```swift
private struct TraceEntry: Decodable {
    let name: String
    let args: Args?

    struct Args: Decodable {
        let title: String?
        let body: String?
        let prompt: String?
        let changes: [ElementChange]?
    }

    enum CodingKeys: String, CodingKey { case name, args }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        args = try? container.decodeIfPresent(Args.self, forKey: .args)
    }
}
```

And read them out in `reply`, keeping the existing draft handling:

```swift
public func reply(
    to message: String, sessionID: String?,
    notes: [ChatNote], page: PageContext?
) async throws -> ChatReply {
    let url = baseURL.appendingPathComponent("chat")
    let response: Response = try await client.postJSON(
        to: url,
        body: Request(
            sessionID: sessionID, message: message, notes: notes,
            page: page.map(PageBody.init)
        ),
        // Above the 60s turn budget on purpose: URLSession's own 60s
        // default would otherwise race the turn clock and surface the
        // same failure under two different messages.
        timeout: 75
    )
    guard !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BackendError.decoding
    }
    let trace = response.toolTrace ?? []
    let draft = trace
        .first { $0.name == "create_note" }
        .flatMap { entry -> ChatPageDraft? in
            guard let title = entry.args?.title else { return nil }
            return ChatPageDraft(title: title, body: entry.args?.body ?? "")
        }
    // Several edit_page calls in one turn merge into one change, so
    // the user gets one receipt and one undo step.
    let edits = PageEditGuard.merge(
        trace.filter { $0.name == "edit_page" }.compactMap { $0.args?.changes }
    )
    let background: BackgroundRequest? = trace.compactMap { entry -> BackgroundRequest? in
        switch entry.name {
        case "set_background":
            guard let prompt = entry.args?.prompt, !prompt.isEmpty else { return nil }
            return .set(prompt: prompt)
        case "clear_background":
            return .clear
        default:
            return nil
        }
    }.last
    return ChatReply(
        text: response.reply, sessionID: response.sessionID, pageDraft: draft,
        pageEdits: edits, backgroundRequest: background
    )
}
```

- [ ] **Step 5: Update the test double**

In `MiraScriptedDoubles.swift`, widen `ScriptedChat` to the new
signature, record the page, and let a test script edits:

```swift
struct ScriptedChat: ChatService {
    var reply = "Scripted reply."
    var sessionID: String? = "scripted-session"
    var delay: Duration = .zero
    var error: Error?
    var pageDraft: ChatPageDraft?
    var pageEdits: [ElementChange] = []
    var backgroundRequest: BackgroundRequest?
    let recorder = SessionRecorder()

    func reply(
        to message: String, sessionID incoming: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        await recorder.record(incoming, notes: notes, page: page)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return ChatReply(
            text: reply, sessionID: sessionID, pageDraft: pageDraft,
            pageEdits: pageEdits, backgroundRequest: backgroundRequest
        )
    }
}
```

Add `pages: [PageContext?]` to `SessionRecorder` and record it.

- [ ] **Step 6: Set the turn budget to 60s**

The ladder only works if the outer clocks are ordered. The HTTP
request is now 75s (Step 4); raise the turn budget to match the spec
by changing the default in `MiraCanvasCoordinator.init`
(MiraCanvasCoordinator.swift:107):

```swift
        timeout: Duration = .seconds(60),
```

Leave `imageTimeout` at 150s -- generation legitimately runs longer,
and Task 7 runs it as its own turn under that budget.

Add the guard test to `MiraCanvasTurnTests` in Task 5, or here if
that file already exists:

```swift
    func testTheTurnClockFiresBeforeTheHTTPClock() {
        let mira = MiraCanvasCoordinator(text: ScriptedText(), chat: ScriptedChat())
        // 60s turn budget vs the 75s request timeout in LiveChatService.
        XCTAssertEqual(mira.turnTimeoutForTesting, .seconds(60))
    }
```

exposing the value with an internal accessor beside `imageTimeout`:

```swift
    /// Test seam: the ladder is only correct if this stays under
    /// LiveChatService's 75s request timeout.
    var turnTimeoutForTesting: Duration { timeout }
```

- [ ] **Step 7: Run the whole suite**

Run: `cd MiraNoteKit && swift test`
Expected: PASS. Existing coordinator tests should compile unchanged
because the old `reply(to:sessionID:notes:)` shape survives as a
protocol extension. Any test that relied on the old 30s default
timeout needs its explicit `timeout:` argument, not a plan change.

- [ ] **Step 8: Commit**

```bash
git add MiraNoteKit/Sources/MiraNoteKit/Chat.swift \
        MiraNoteKit/Sources/MiraNoteKit/Networking/LiveChatService.swift \
        MiraNoteKit/Tests/MiraNoteKitTests/
git commit -m "feat(ios): send the page with a canvas turn and read edits back

Refs #41"
```

---

### Task 5: Turn a canvas ask into a page edit

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraIntent.swift:114-165, 207-246`
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraCanvasTurnTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: `MiraIntent.canvasTurn(String, PageContext, handles: [String: CanvasItem.ID])`
  replacing `.converse` and `.organize`;
  `MiraOutcome.pageEdited([ElementChange], handles: [String: CanvasItem.ID])`
  and `MiraOutcome.backgroundRequested(BackgroundRequest, reply: String)`;
  `MiraCanvasCoordinator.renderPage: (() -> Data?)?`.

  The outcome carries the raw `ElementChange`s and the handle table,
  not `ResolvedChange`s: guards run on the main actor at settle time,
  against the page as it stands then, because `perform` runs off the
  main actor and the page may have moved under it.

- [ ] **Step 1: Write the failing test**

Create `MiraNoteKit/Tests/MiraNoteKitTests/MiraCanvasTurnTests.swift`:

```swift
import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraCanvasTurnTests: XCTestCase {
    private func editor() -> CanvasViewModel {
        let item = CanvasItem(
            content: .text(TextBlock(text: "Noodle shop", pointSize: 30)),
            position: CGPoint(x: 180, y: 300),
            size: CGSize(width: 304, height: 44)
        )
        let model = CanvasViewModel(memory: Memory(items: [item]))
        model.canvasWidth = 393
        return model
    }

    private func coordinator(_ chat: ScriptedChat) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(), chat: chat,
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            receiptDismiss: .seconds(60)
        )
    }

    private func waitUntil(
        _ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testAnEditLandsOnTheCanvasWithOneReceipt() async {
        var chat = ScriptedChat()
        chat.reply = "Moved it up."
        chat.pageEdits = [ElementChange(handle: "t1", x: 28, y: 24)]
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("move the title above the photo", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        let item = board.items[0]
        XCTAssertEqual(item.position.y - item.size.height / 2, 24, accuracy: 0.5)
        board.undo()
        XCTAssertEqual(item.id, board.items[0].id)
        XCTAssertFalse(board.canUndo)
    }

    func testTheCanvasTurnSendsAPageMapNotAFlatNote() async {
        var chat = ScriptedChat()
        chat.reply = "Sure."
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("how does this page look", editor: board)
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        let pages = await chat.recorder.pages
        XCTAssertEqual(pages.first??.map.width, 393)
        XCTAssertEqual(pages.first??.map.elements.first?.handle, "t1")
    }

    func testAnEditNamingNothingFailsWithClarifyAndLeavesTheCanvasAlone() async {
        var chat = ScriptedChat()
        chat.reply = "Done."
        chat.pageEdits = [ElementChange(handle: "t9", x: 10)]
        let board = editor()
        let before = board.items[0].position
        let mira = coordinator(chat)

        mira.ask("move that thing", editor: board)
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure(let failure) = mira.phase else {
            return XCTFail("expected a failure card")
        }
        XCTAssertEqual(failure.kind, .clarify)
        XCTAssertEqual(board.items[0].position, before)
        XCTAssertFalse(board.canUndo)
    }

    func testTidyOnASingleElementPageAsksRatherThanPretending() async {
        var chat = ScriptedChat()
        chat.reply = "There is only one thing here."
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("tidy this page up", editor: board)
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure(let failure) = mira.phase else {
            return XCTFail("expected a clarify card")
        }
        XCTAssertEqual(failure.kind, .clarify)
    }

    func testTheRenderedPageRidesAlongWhenTheClosureIsWired() async {
        var chat = ScriptedChat()
        chat.reply = "ok"
        let board = editor()
        let mira = coordinator(chat)
        mira.renderPage = { Data([0xFF, 0xD8, 0xFF]) }

        mira.ask("how does this look", editor: board)
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        let pages = await chat.recorder.pages
        XCTAssertEqual(pages.first??.image?.count, 3)
    }

    func testNoRenderClosureIsNotAFailure() async {
        var chat = ScriptedChat()
        chat.reply = "ok"
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("how does this look", editor: board)
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        let pages = await chat.recorder.pages
        XCTAssertNil(pages.first??.image)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd MiraNoteKit && swift test --filter MiraCanvasTurnTests`
Expected: FAIL to compile, `value of type 'MiraCanvasCoordinator' has no member 'renderPage'`

- [ ] **Step 3: Replace the converse intent**

In `MiraIntent.swift`, replace the `.converse` case and the three
`ChatNote(page:)` call sites. The tidy/organize keywords stop
returning `.organize` and fall through to the canvas turn (Meng's
call: model-driven rearrange, with `quickOrganize` kept only as the
offline fallback in Task 7).

```swift
    /// A canvas turn: the page rides along as a map, and whatever the
    /// model does with it comes back as edits.
    case canvasTurn(String, PageContext, handles: [String: CanvasItem.ID])
```

Delete `case organize` and `case converse` from the enum and every
`switch` over it, and in `classify` replace the tidy branch and the
final fallthrough with:

```swift
        // Layout asks used to hit a hardcoded local rearrange; they
        // now go to the model, which can see where things actually are.
        return .canvasTurn(prompt, context, handles: handles)
```

where `context` and `handles` come from a new helper on `MiraIntent`:

```swift
    @MainActor
    static func pageContext(
        editor: CanvasViewModel, render: (() -> Data?)?
    ) -> (PageContext, [String: CanvasItem.ID]) {
        let (map, handles) = PageMap.build(
            from: editor.composedMemory(),
            canvasWidth: editor.canvasWidth ?? 393
        )
        return (PageContext(map: map, image: render?()), handles)
    }
```

`classify` gains a `render: (() -> Data?)?` parameter; the coordinator
passes its own `renderPage`.

In `perform`, the new case:

```swift
        case .canvasTurn(let prompt, let context, let handles):
            let reply = try await chat.reply(
                to: prompt, sessionID: sessionID, notes: [], page: context
            )
            if let landed = MiraIntent.landedDraft(from: reply) {
                return landed
            }
            if let background = reply.backgroundRequest {
                return .backgroundRequested(background, reply: reply.text)
            }
            if !reply.pageEdits.isEmpty {
                return .pageEdited(reply.pageEdits, handles: handles)
            }
            return .reply(reply.text, sessionID: reply.sessionID)
```

Add to `MiraOutcome`:

```swift
    /// Handles are resolved on the main actor at settle time, against
    /// the page as it stands then.
    case pageEdited([ElementChange], handles: [String: CanvasItem.ID])
    case backgroundRequested(BackgroundRequest, reply: String)
```

And a verb: `case .canvasTurn: return "Working on the page..."`.

- [ ] **Step 4: Settle it on the coordinator**

In `MiraCanvasCoordinator.swift`, add the closure beside `prepareTurn`:

```swift
    /// Renders the page as the user sees it, wired by the view (the
    /// renderer lives in the App layer). Nil in tests and previews --
    /// Mira then answers from the map alone, which is not a failure.
    public var renderPage: (() -> Data?)?
```

Pass it into classification:

```swift
            let intent = MiraIntent.classify(trimmed, editor: editor, render: self.renderPage)
```

Add the settle branch:

```swift
        case .pageEdited(let changes, let handles):
            let resolved = PageEditGuard.resolve(
                changes, handles: handles, canvasWidth: editor.canvasWidth ?? 393
            )
            guard editor.applyPageEdits(resolved) else {
                refillPrompt = lastPrompt
                phase = .failure(MiraFailure(
                    kind: .clarify,
                    message: "I could not tell which piece you meant -- which one should I move?",
                    chips: ["Try again"]
                ))
                return
            }
            showReceipt(Self.receipt(for: resolved, editor: editor), editor: editor)
```

Add the receipt rule table -- the copy is the app's, never the
model's, so the confirmation strip keeps one voice:

```swift
    /// The receipt says what changed, in the app's voice. One line.
    static func receipt(
        for changes: [ResolvedChange], editor: CanvasViewModel
    ) -> MiraReceipt {
        let kept = "Everything else stayed put."
        if changes.count >= 3 {
            return MiraReceipt(changed: "Rearranged the page.", kept: kept)
        }
        let noun = changes.count == 1
            ? Self.noun(for: changes[0].id, editor: editor) : "a few things"
        let moved = changes.contains { $0.x != nil || $0.y != nil }
        let resized = changes.contains { $0.w != nil || $0.h != nil || $0.pointSize != nil }
        if moved && !resized { return MiraReceipt(changed: "Moved \(noun).", kept: kept) }
        if resized && !moved { return MiraReceipt(changed: "Resized \(noun).", kept: kept) }
        if changes.contains(where: { $0.colorName != nil }) {
            return MiraReceipt(changed: "Recolored \(noun).", kept: kept)
        }
        return MiraReceipt(changed: "Adjusted \(noun).", kept: kept)
    }

    private static func noun(for id: CanvasItem.ID, editor: CanvasViewModel) -> String {
        switch editor.item(id)?.content {
        case .text(let block): return block.pointSize >= 24 ? "the title" : "the text"
        case .image: return "the photo"
        case .sticker: return "the sticker"
        case .sound: return "the sound"
        case nil: return "it"
        }
    }
```

- [ ] **Step 5: Guard the nothing-to-arrange case**

In `classify`, before returning `.canvasTurn`, short-circuit a layout
ask on a page that has nothing to lay out:

```swift
        let layoutCue = ["tidy", "layout", "organize", "arrange"].contains { lowered.contains($0) }
        if layoutCue && editor.items.count < 2 {
            return .clarifyNothingToArrange
        }
```

with the matching `perform` case:

```swift
        case .clarifyNothingToArrange:
            throw MiraClarifyError(
                question: "There is not much on this page to arrange yet -- add a little first?",
                chips: ["Add a soft title"]
            )
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd MiraNoteKit && swift test --filter MiraCanvasTurnTests`
Expected: PASS, 6 tests

- [ ] **Step 7: Run the whole suite and fix the fallout**

Run: `cd MiraNoteKit && swift test`
Expected: PASS. Existing tests referencing `.converse` or `.organize`
need updating to the new cases -- update them, do not delete them.
`MiraCanvasCoordinatorTests` and `MiraBackgroundTurnTests` are the
likely ones.

- [ ] **Step 8: Commit**

```bash
git add MiraNoteKit/
git commit -m "feat(ios): let a canvas ask move and restyle real elements

Refs #41"
```

---

### Task 6: Render the page and wire it up

**Files:**
- Create: `App/Sources/Screens/Editor/CanvasSnapshot.swift`
- Modify: `App/Sources/Screens/Editor/CanvasScene.swift:87` (where
  `mira.prepareTurn` is already wired)
- Test: `App/UITests` smoke, plus a manual pass

**Interfaces:**
- Consumes: `MiraCanvasCoordinator.renderPage` (Task 5),
  `StaticPageView` (`App/Sources/Screens/Reading/PageRendering.swift:8`).
- Produces: `CanvasSnapshot.jpeg(memory:canvasWidth:) -> Data?`.

- [ ] **Step 1: Write the renderer**

Create `App/Sources/Screens/Editor/CanvasSnapshot.swift`:

```swift
import MiraNoteKit
import SwiftUI
import UIKit

/// The page as the user sees it, for Mira's look_at_page.
///
/// Rendered at the REAL canvas width, not StaticPageView's 360
/// default: the point is to show the model what is on screen.
enum CanvasSnapshot {
    /// Long edge cap. The canvas scrolls without limit, so a tall page
    /// would otherwise be enormous. Coarse is fine -- precision lives
    /// in the page map; this image only carries impression.
    static let longEdge: CGFloat = 1536

    @MainActor
    static func jpeg(memory: Memory, canvasWidth: CGFloat) -> Data? {
        let renderer = ImageRenderer(
            content: StaticPageView(
                memory: memory, designWidth: canvasWidth, showsSound: false
            )
        )
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return downscaled(image).jpegData(compressionQuality: 0.7)
    }

    @MainActor
    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longEdge else { return image }
        let scale = longEdge / longest
        let target = CGSize(
            width: image.size.width * scale, height: image.size.height * scale
        )
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
```

- [ ] **Step 2: Wire the closure beside `prepareTurn`**

In `App/Sources/Screens/Editor/CanvasScene.swift`, line 87 already
reads `mira.prepareTurn = { await lookAtUnseenPhotos() }`. Add
directly under it, matching the surrounding capture style:

```swift
mira.renderPage = {
    CanvasSnapshot.jpeg(
        memory: editor.composedMemory(),
        canvasWidth: editor.canvasWidth ?? 393
    )
}
```

Read the surrounding lines first: whichever lifecycle hook holds the
`prepareTurn` assignment is where this belongs too.

- [ ] **Step 3: Build the app**

Run:
```bash
xcodebuild -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Verify on the simulator with the backends up**

Start the backends (`./start-all.sh` in miranote-api; the chat POC on
:8003 and the image POC on :8002 both need to be running). Then run
the app, open a page with a title and a photo, and try in order:

1. "move the title above the photo" -- the title moves, one receipt,
   Revert restores it whole.
2. "make the photo bigger" -- it grows, one receipt.
3. "the title is too small" -- the text grows AND its box grows with
   it; nothing below is overlapped.
4. "how does this page look" -- a reply that describes the actual
   arrangement (this one proves look_at_page reached Gemini).
5. "tidy this page up" -- several elements move, one receipt reading
   "Rearranged the page.", one Revert restores all of them.

- [ ] **Step 5: Verify the install is real before believing the screen**

Screenshot the simulator, then confirm the binary actually carries the
new code -- a timestamp alone proves nothing:

```bash
grep -c "Rearranged the page" \
  ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Bundle/Application/*/MiraNote.app/Frameworks/MiraNote.debug.dylib
```
Expected: at least 1.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/
git commit -m "feat(ios): render the page for Mira to look at

Refs #41"
```

---

### Task 7: Slow background work, and the offline fallback

**Files:**
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator.swift`
- Modify: `MiraNoteKit/Sources/MiraNoteKit/ViewModels/MiraCanvasCoordinator+Images.swift`
- Test: `MiraNoteKit/Tests/MiraNoteKitTests/MiraCanvasTurnTests.swift` (append)

**Interfaces:**
- Consumes: `MiraOutcome.backgroundRequested` (Task 5), the existing
  `setBackground` image path in `+Images.swift`.
- Produces: no new public API; a defined second turn.

**Why:** by the time the app reads the instruction the chat turn has
settled -- `turnTask` is nil, phase is `.reply`. Without an explicit
new turn, Stop has nothing to cancel and a late receipt can land on
top of whatever the user did next.

- [ ] **Step 1: Write the failing test**

Append to `MiraCanvasTurnTests.swift`:

```swift
    func testABackgroundRequestRunsAsAFreshStoppableTurn() async {
        var chat = ScriptedChat()
        chat.reply = "Painting a dusk sky."
        chat.backgroundRequest = .set(prompt: "a quiet dusk sky")
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("change the background", editor: board)
        await waitUntil { mira.isWorking }
        XCTAssertTrue(mira.isWorking, "the slow work must be a turn Stop can cancel")

        mira.stop()
        XCTAssertFalse(mira.isWorking)
        XCTAssertEqual(mira.refillPrompt, "change the background")
    }

    func testTidyFallsBackToLocalRearrangeWhenTheBackendIsDown() async {
        var chat = ScriptedChat()
        chat.error = BackendError.unreachable
        let extra = CanvasItem(
            content: .text(TextBlock(text: "second", pointSize: 15)),
            position: CGPoint(x: 180, y: 500), size: CGSize(width: 304, height: 44)
        )
        let board = editor()
        board.addItemForTesting(extra)
        let before = board.items.map(\.position)
        let mira = coordinator(chat)

        mira.ask("tidy this page up", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        XCTAssertNotEqual(board.items.map(\.position), before)
    }
```

If `CanvasViewModel` has no test seam for appending an item, use the
existing public `addText` instead of inventing `addItemForTesting`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd MiraNoteKit && swift test --filter MiraCanvasTurnTests`
Expected: FAIL -- `isWorking` is false after the reply settles

- [ ] **Step 3: Settle the background request as a new turn**

In `MiraCanvasCoordinator.settle`:

```swift
        case .backgroundRequested(let request, let reply):
            startBackgroundTurn(request, reply: reply, editor: editor)
```

and beside `run`:

```swift
    /// Slow image work Mira asked for. It is a new turn, not the tail
    /// of the chat turn: the chat turn has already settled, so without
    /// its own generation Stop would have nothing to cancel and a late
    /// receipt could land on the user's next edit.
    private func startBackgroundTurn(
        _ request: BackgroundRequest, reply: String, editor: CanvasViewModel
    ) {
        switch request {
        case .clear:
            // The same call the existing .backgroundCleared branch
            // makes (MiraCanvasCoordinator+Images.swift:15).
            editor.beginChange()
            editor.setBackground(fileName: "")
            showReceipt(MiraReceipt(
                changed: "Cleared the backdrop.",
                kept: "Your words and photos are unchanged."
            ), editor: editor)
        case .set(let prompt):
            cancelTurn()
            let generation = turnGeneration
            phase = .working(verb: "Painting the backdrop...")
            turnTask = Task {
                await run(
                    .setBackground(prompt: prompt), prompt: lastPrompt,
                    editor: editor, generation: generation
                )
            }
        }
    }
```

`.setBackground(prompt:)` is the existing `MiraIntent` case that
`+Images.swift` already knows how to perform and settle -- this reuses
it wholesale, only changing what starts it.

- [ ] **Step 4: Add the offline rearrange fallback**

In `run`'s `catch` block, before the generic failure:

```swift
        } catch {
            indicator.cancel()
            guard !Task.isCancelled, turnGeneration == generation else { return }
            // A deterministic local rearrange beats a failure card for
            // "tidy this page" -- quickOrganize needs no network.
            if case .canvasTurn(let words, _, _) = intent,
               Self.isLayoutAsk(words), editor.items.count >= 2 {
                editor.quickOrganize(canvasWidth: editor.canvasWidth ?? 393)
                showReceipt(MiraReceipt(
                    changed: "Tidied the layout.",
                    kept: "Your words and photos are unchanged."
                ), editor: editor)
                return
            }
            refillPrompt = prompt
            phase = .failure(Self.failure(for: error))
        }
```

with:

```swift
    /// The layout vocabulary, shared by the offline fallback and the
    /// nothing-to-arrange guard so they cannot drift apart.
    nonisolated static func isLayoutAsk(_ words: String) -> Bool {
        let lowered = words.lowercased()
        return ["tidy", "layout", "organize", "arrange"].contains { lowered.contains($0) }
    }
```

Use this same helper in Task 5 Step 5's guard, replacing the inline
array there.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd MiraNoteKit && swift test --filter MiraCanvasTurnTests`
Expected: PASS, 8 tests

- [ ] **Step 6: Run the whole suite**

Run: `cd MiraNoteKit && swift test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add MiraNoteKit/
git commit -m "feat(ios): run Mira's background work as its own turn

Refs #41"
```

---

### Task 8: Open the PR

- [ ] **Step 1: Full test pass**

```bash
cd MiraNoteKit && swift test
```
Expected: all pass.

- [ ] **Step 2: Build the app and run the UI tests**

```bash
xcodebuild -project MiraNote.xcodeproj -scheme MiraNote \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

- [ ] **Step 3: Lint from the repo root**

```bash
swiftlint
```
Run from the repo root, never from `MiraNoteKit/` -- running it there
reports about 35 phantom violations.

- [ ] **Step 4: Check the repo rules**

From the `.github` checkout:
```bash
PYTHONPATH=. python3 -m checks.no_cjk_or_emoji <path-to>/miranote-ios
```
Expected: no new violations from `MiraNoteKit/Sources` or `App/Sources`.

- [ ] **Step 5: Open the PR**

Use the create-pr skill. Base `main`, never stacked. Conventional
Commit title under 72 chars with a whitelisted scope, e.g.
`feat(ios): let Mira read the canvas layout and edit elements`. Body
must contain `Closes #41`. Note in the body that miranote-api#38 must
be deployed for the feature to work.

---

## Notes for the reviewer

- **Check Task 3 hardest.** A mixed change set must be exactly one
  undo step. If `applyPageEdits` ever calls `setTextPointSize`,
  `setTextColorName`, `bringToFront` or `sendToBack`, Revert silently
  becomes a lie -- and the test that catches it is the
  `XCTAssertFalse(model.canUndo)` after a single `undo()`.
- **Grep the diff for `360`.** Every occurrence outside
  `PageRendering.swift`'s existing default is a bug.
- Point sizes must be applied before positions, with the re-measure
  between. Reordering those loops looks harmless and is not.
- A failed `look_at_page` must never fail a turn. Neither must an
  unwired `renderPage`.
