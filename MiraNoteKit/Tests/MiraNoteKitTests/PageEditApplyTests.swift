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
        _ body: String = "hello", top: CGFloat = 100, size: CGFloat = 17
    ) -> CanvasItem {
        CanvasItem(
            content: .text(TextBlock(text: body, pointSize: size)),
            position: CGPoint(x: 180, y: top),
            size: CGSize(width: 304, height: 44)
        )
    }

    /// THE test. setTextPointSize, setTextColorName, bringToFront and
    /// sendToBack each call beginChange() themselves, while revert() pops
    /// exactly one snapshot. Route the apply path through them and the
    /// user taps Revert on a five-field change and watches most of it
    /// stay -- with the receipt claiming otherwise.
    func testAMixedChangeSetIsExactlyOneUndoStep() {
        let first = textItem("one", top: 100)
        let second = textItem("two", top: 300)
        let model = editor([first, second])

        let landed = model.applyPageEdits([
            ResolvedChange(id: first.id, x: 20, y: 20, pointSize: 34, colorName: "forest", layer: .front),
            ResolvedChange(id: second.id, x: 20, y: 400, colorName: "sage", layer: .back)
        ])
        XCTAssertTrue(landed)

        model.undo()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.item(first.id)?.position, first.position)
        XCTAssertEqual(model.item(second.id)?.position, second.position)
        XCTAssertEqual(model.item(first.id)?.size, first.size)
        if case .text(let block) = model.item(first.id)?.content {
            XCTAssertEqual(block.pointSize, 17)
            XCTAssertEqual(block.colorName, "ink")
        } else {
            XCTFail("expected the text block back")
        }
        XCTAssertFalse(model.canUndo, "one change must leave exactly one snapshot")
    }

    func testPositionsAreTopLeftAndConvertBackToCenters() {
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, x: 40, y: 60)])
        let moved = model.item(item.id)!
        XCTAssertEqual(moved.position.x, 40 + moved.size.width / 2)
        XCTAssertEqual(moved.position.y, 60 + moved.size.height / 2)
    }

    func testRaisingThePointSizeGrowsTheBoxBeforePositionsLand() {
        let body = "a reasonably long line of text that wraps more than once"
        let item = textItem(body, top: 100, size: 15)
        let model = editor([item])
        let grown = Memory.estimatedTextHeight(body, pointSize: 40, width: 304)

        model.applyPageEdits([ResolvedChange(id: item.id, y: 200, pointSize: 40)])

        let after = model.item(item.id)!
        XCTAssertEqual(after.size.height, grown, accuracy: 0.5)
        // The requested top edge still wins after the re-measure.
        XCTAssertEqual(after.position.y - after.size.height / 2, 200, accuracy: 0.5)
    }

    func testPointSizeAloneStillGrowsTheBox() {
        let body = "a reasonably long line of text that wraps more than once"
        let item = textItem(body, top: 100, size: 15)
        let model = editor([item])
        let before = model.item(item.id)!.size.height

        model.applyPageEdits([ResolvedChange(id: item.id, pointSize: 40)])

        XCTAssertGreaterThan(model.item(item.id)!.size.height, before)
    }

    func testLayerFrontAndBackRestackWithoutExtraSnapshots() {
        let first = textItem("one", top: 100)
        let second = textItem("two", top: 300)
        let model = editor([first, second])

        model.applyPageEdits([ResolvedChange(id: first.id, layer: .front)])
        XCTAssertGreaterThan(model.item(first.id)!.zIndex, model.item(second.id)!.zIndex)

        model.applyPageEdits([ResolvedChange(id: first.id, layer: .back)])
        XCTAssertLessThan(model.item(first.id)!.zIndex, model.item(second.id)!.zIndex)

        model.undo()
        model.undo()
        XCTAssertFalse(model.canUndo, "two applies, two snapshots -- no more")
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

    func testAWholePageRearrangeIsStillOneStep() {
        let items = (0..<5).map { textItem("block \($0)", top: CGFloat($0) * 100 + 50) }
        let model = editor(items)
        let before = items.map(\.position)

        model.applyPageEdits(items.enumerated().map { index, item in
            ResolvedChange(id: item.id, x: 28, y: Double(index) * 70 + 28)
        })

        XCTAssertNotEqual(model.items.map(\.position), before)
        model.undo()
        XCTAssertEqual(model.items.map(\.position), before)
        XCTAssertFalse(model.canUndo)
    }

    // MARK: The page's edges are walls to the model's arithmetic

    func testAnEscapePastTheRightEdgeLandsFullyInside() {
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, x: 5000)])
        let moved = model.item(item.id)!
        XCTAssertLessThanOrEqual(moved.position.x + moved.size.width / 2, 393,
                                 "the right edge must stay inside the page")
    }

    func testANegativeLeftLandsAtTheWall() {
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, x: -500)])
        let moved = model.item(item.id)!
        XCTAssertEqual(moved.position.x - moved.size.width / 2, 0, accuracy: 0.5)
    }

    func testAWidthBeyondThePageIsClampedToThePage() {
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, w: 9000)])
        XCTAssertEqual(model.item(item.id)!.size.width, 393)
    }

    func testANegativeTopLandsAtTheTop() {
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, y: -300)])
        let moved = model.item(item.id)!
        XCTAssertEqual(moved.position.y - moved.size.height / 2, 0, accuracy: 0.5)
    }

    func testAnInBoundsEditIsUntouchedByTheWalls() {
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, x: 40, y: 60, w: 200)])
        let moved = model.item(item.id)!
        XCTAssertEqual(moved.position.x - moved.size.width / 2, 40, accuracy: 0.5)
        XCTAssertEqual(moved.position.y - moved.size.height / 2, 60, accuracy: 0.5)
        XCTAssertEqual(moved.size.width, 200)
    }

    func testADeepYBelowThePageIsKept() {
        // The canvas scrolls down without limit -- the bottom is not a
        // wall, and pinning that keeps a future guard from adding one.
        let item = textItem()
        let model = editor([item])
        model.applyPageEdits([ResolvedChange(id: item.id, y: 5000)])
        let moved = model.item(item.id)!
        XCTAssertEqual(moved.position.y - moved.size.height / 2, 5000, accuracy: 0.5)
    }
}
