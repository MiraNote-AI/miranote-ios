import MiraNoteKit
import XCTest
@testable import MiraNote

/// The lifted photo's editor works on its own visit: its Undo takes back
/// only its own steps, and Cancel stops a running studio call and drops
/// a result that still arrives.
@MainActor
final class PhotoEditVisitTests: XCTestCase {
    /// The mock studio, with a stylize that takes its time.
    private struct SlowStudio: ImageStudioService {
        let base = MockImageStudioService()
        func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
            try await base.generate(kind: kind, prompt: prompt)
        }
        func cutout(image: Data, target: String?) async throws -> Data {
            try? await Task.sleep(for: .milliseconds(600))
            return try await base.cutout(image: image, target: target)
        }
        func stylize(image: Data, instruction: String) async throws -> Data {
            try? await Task.sleep(for: .milliseconds(600))
            return try await base.stylize(image: image, instruction: instruction)
        }
        func outline(image: Data) async throws -> Data { try await base.outline(image: image) }
        func describe(image: Data) async throws -> String { try await base.describe(image: image) }
    }

    /// A page holding one stored photo, and the photo's id.
    private func makePhoto() throws -> (CanvasViewModel, CanvasItem.ID) {
        let fileName = try ImageFileStore().save(MockImageStudioService.tinyPNG, id: UUID())
        let ref = ImageRef(displayName: "photo", fileName: fileName)
        let editor = CanvasViewModel(memory: Memory())
        let id = try XCTUnwrap(editor.addImages([ref], around: CGPoint(x: 180, y: 200)).first)
        return (editor, id)
    }

    private func controller(_ editor: CanvasViewModel, _ id: CanvasItem.ID,
                            studio: ImageStudioService = MockImageStudioService()) -> PhotoEditController {
        PhotoEditController(itemID: id, editor: editor, studio: studio, onEdited: {}, onClose: {})
    }

    private func fileName(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        guard case .image(let ref) = editor.item(id)?.content else { return nil }
        return ref.fileName
    }

    func testUndoTakesBackOnlyThisVisitsOwnSteps() throws {
        let (editor, id) = try makePhoto()
        let photoEdit = controller(editor, id)
        XCTAssertFalse(photoEdit.canUndo, "nothing of this visit yet")

        photoEdit.tap(.bw)
        XCTAssertTrue(photoEdit.canUndo)
        photoEdit.undo()
        XCTAssertFalse(photoEdit.canUndo)
        guard case .image(let ref) = editor.item(id)?.content else { return XCTFail("photo gone") }
        XCTAssertEqual(ref.filterName, "")
    }

    func testUndoStepsAsideWhenSomethingElseIsNewer() throws {
        let (editor, id) = try makePhoto()
        // An earlier visit's B&W, kept with Done; then a text block.
        let earlier = controller(editor, id)
        earlier.tap(.bw)
        let text = editor.addText("Dinner with Mom", at: CGPoint(x: 180, y: 400))

        let visit = controller(editor, id)
        XCTAssertFalse(visit.canUndo, "the newest step is the text block, not this visit's")
        visit.undo()
        XCTAssertNotNil(editor.item(text), "the text block stays")
    }

    func testCancelDropsAnAIEditThatLandsLater() async throws {
        let (editor, id) = try makePhoto()
        let original = try XCTUnwrap(fileName(editor, id))
        let photoEdit = controller(editor, id, studio: SlowStudio())
        photoEdit.tap(.ai)
        photoEdit.prompt = "make it autumn"
        photoEdit.runComposer()
        XCTAssertTrue(photoEdit.working)

        // What the header Cancel does.
        photoEdit.cancelWork()
        if let start = photoEdit.visitStart { editor.restoreImage(itemID: id, to: start) }
        try await Task.sleep(for: .milliseconds(1_200))

        XCTAssertEqual(fileName(editor, id), original, "the late result did not land")
        XCTAssertEqual(editor.changeCount, 1, "and recorded no step after placing the photo")
    }

    func testCancelDropsACutoutThatLandsLater() async throws {
        let (editor, id) = try makePhoto()
        let photoEdit = controller(editor, id, studio: SlowStudio())
        photoEdit.tap(.cutout)
        photoEdit.runComposer()
        photoEdit.cancelWork()
        try await Task.sleep(for: .milliseconds(1_200))
        guard case .image = editor.item(id)?.content else { return XCTFail("the photo became a sticker") }
    }
}
