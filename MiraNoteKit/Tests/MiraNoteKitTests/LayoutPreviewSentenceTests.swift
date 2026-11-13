import CoreGraphics
import XCTest
@testable import MiraNoteKit

/// #187 review: a photo's sentence (the import's vision describe) can land
/// while layout templates are tried. Each card, Cancel and Done put back a
/// page laid out from the one kept when the strip opened, which has no
/// sentence yet; the sentence must survive all three.
final class LayoutPreviewSentenceTests: XCTestCase {
    private let sentence = "a beach at dusk"

    private func page() -> [CanvasItem] {
        let title = CanvasItem(content: .text(TextBlock(text: "A day by the sea", pointSize: 20, colorName: "forest",
                                                        fontName: "Futura", backgroundColorName: "sand")),
                               position: CGPoint(x: 180, y: 40), size: CGSize(width: 200, height: 40))
        let photos = (0..<3).map { index in
            CanvasItem(content: .image(ImageRef(displayName: "photo \(index)", fileName: "photo\(index).png")),
                       position: CGPoint(x: 100, y: 160 + CGFloat(index) * 200),
                       size: CGSize(width: 160, height: 120))
        }
        return [title] + photos
    }

    /// What CanvasScene.laidOut does with the page kept when the strip opened.
    private func laid(_ template: PageLayout.Template, _ items: [CanvasItem]) -> [CanvasItem] {
        PageLayout.apply(template, to: items, pageWidth: 360, textHeight: { _, _ in 40 },
                         photoAspect: { $0.size.height / $0.size.width })
    }

    private func summary(_ items: [CanvasItem]?, _ id: CanvasItem.ID) -> String? {
        guard case .image(let ref) = items?.first(where: { $0.id == id })?.content else { return nil }
        return ref.summary
    }

    @MainActor private func summary(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        summary(editor.items, id)
    }

    private func places(_ items: [CanvasItem]) -> [CGPoint] { items.map(\.position) }

    @MainActor func testASentenceLandingWhileTryingSurvivesTheNextCard() {
        let original = page()
        let editor = CanvasViewModel(memory: Memory(items: original))
        let photo = original[2].id
        editor.previewLayout(laid(.tShape, original))
        editor.setImageSummary(itemID: photo, to: sentence)
        editor.previewLayout(laid(.onePlusTwo, original))
        XCTAssertEqual(summary(editor, photo), sentence)
        XCTAssertEqual(places(editor.items), places(laid(.onePlusTwo, original)), "the card shows as laid out")
        XCTAssertEqual(summary(editor.autosavedMemory?.items, photo), sentence,
                       "the background autosave files the sentence with the page as it was")
    }

    @MainActor func testASentenceLandingWhileTryingSurvivesCancel() {
        let original = page()
        let editor = CanvasViewModel(memory: Memory(items: original))
        let photo = original[2].id
        let depth = editor.undoDepth
        editor.previewLayout(laid(.tShape, original))
        editor.setImageSummary(itemID: photo, to: sentence)
        editor.cancelLayout(to: original)
        XCTAssertEqual(summary(editor, photo), sentence)
        XCTAssertEqual(places(editor.items), places(original), "Cancel puts every element back")
        XCTAssertEqual(editor.undoDepth, depth, "and records nothing")
    }

    @MainActor func testASentenceLandingBeforeAnyCardSurvivesCancelAndACard() {
        let original = page()
        let editor = CanvasViewModel(memory: Memory(items: original))
        let photo = original[2].id
        editor.setImageSummary(itemID: photo, to: sentence)
        editor.cancelLayout(to: original)
        XCTAssertEqual(summary(editor, photo), sentence, "the strip opened and closed with nothing tried")
        editor.previewLayout(laid(.tShape, original))
        XCTAssertEqual(summary(editor, photo), sentence, "a card laid out from the page kept at the strip's opening")
    }

    @MainActor func testASentenceLandingWhileTryingSurvivesDoneAndItsUndo() {
        let original = page()
        let editor = CanvasViewModel(memory: Memory(items: original))
        let photo = original[2].id
        let depth = editor.undoDepth
        editor.previewLayout(laid(.tShape, original))
        editor.setImageSummary(itemID: photo, to: sentence)
        editor.previewLayout(laid(.onePlusTwo, original))
        editor.commitLayout(from: original)
        XCTAssertEqual(summary(editor, photo), sentence, "Done keeps the sentence")
        XCTAssertEqual(editor.undoDepth, depth + 1, "Done is one undo step")
        editor.undo()
        XCTAssertEqual(places(editor.items), places(original), "the undo puts the page back")
        XCTAssertEqual(summary(editor, photo), sentence, "and keeps the sentence")
    }
}
