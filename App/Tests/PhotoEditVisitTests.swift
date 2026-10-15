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

    // MARK: Done during an AI edit, then the same photo again

    private func filterName(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        guard case .image(let ref) = editor.item(id)?.content else { return nil }
        return ref.filterName
    }

    private struct RunningEdit {
        let editor: CanvasViewModel
        let id: CanvasItem.ID
        let first: PhotoEditController
    }

    /// Visit 1 runs an AI edit and is closed with Done while it spins.
    private func doneDuringAnAIEdit() throws -> RunningEdit {
        let (editor, id) = try makePhoto()
        let first = controller(editor, id, studio: SlowStudio())
        first.tap(.ai)
        first.prompt = "make it autumn"
        first.runComposer()
        XCTAssertTrue(first.working)
        return RunningEdit(editor: editor, id: id, first: first)
    }

    func testReopeningAPhotoWhileItsEditRunsIsTheSameVisitShowingTheWork() throws {
        let run = try doneDuringAnAIEdit()
        let (editor, id, first) = (run.editor, run.id, run.first)
        let reopened = PhotoEditController.opening(id, current: first) { controller(editor, id, studio: SlowStudio()) }
        XCTAssertTrue(reopened === first, "never two controllers for one photo")
        XCTAssertTrue(reopened.working, "the reopened editor shows the edit still on its way")
    }

    func testAFilterChosenAfterReopeningSurvivesTheEarlierEditAndCanBeUndone() async throws {
        let run = try doneDuringAnAIEdit()
        let (editor, id, first) = (run.editor, run.id, run.first)
        let original = try XCTUnwrap(fileName(editor, id))
        let reopened = PhotoEditController.opening(id, current: first) { controller(editor, id, studio: SlowStudio()) }
        // B&W while the earlier edit still runs: it waits, or it lasts --
        // never applied and then wiped by the late result.
        reopened.tap(.bw)
        let tookAtOnce = filterName(editor, id) == "bw"
        try await Task.sleep(for: .milliseconds(1_200))
        if tookAtOnce {
            XCTAssertEqual(filterName(editor, id), "bw", "the late result wiped this visit's B&W")
            XCTAssertTrue(reopened.canUndo, "and took its Undo with it")
            return
        }
        reopened.tap(.bw)
        XCTAssertEqual(filterName(editor, id), "bw")
        XCTAssertTrue(reopened.canUndo, "this visit's B&W can be undone from its own Undo")
        reopened.undo()
        XCTAssertEqual(filterName(editor, id), "")
        XCTAssertNotEqual(fileName(editor, id), original, "the edit kept with Done is not this visit's to undo")
        XCTAssertFalse(reopened.canUndo)
    }

    func testCancellingTheReopenedVisitKeepsTheEditKeptWithDone() async throws {
        let run = try doneDuringAnAIEdit()
        let (editor, id, first) = (run.editor, run.id, run.first)
        let original = try XCTUnwrap(fileName(editor, id))
        let reopened = PhotoEditController.opening(id, current: first) { controller(editor, id, studio: SlowStudio()) }
        try await Task.sleep(for: .milliseconds(1_200))
        let edited = try XCTUnwrap(fileName(editor, id))
        XCTAssertNotEqual(edited, original, "the AI edit kept with Done landed")

        reopened.cancelVisit()
        XCTAssertEqual(fileName(editor, id), edited, "Cancel on a visit that changed nothing keeps it")
    }

    func testCancellingTheReopenedVisitWhileTheEditRunsLetsItLand() async throws {
        let run = try doneDuringAnAIEdit()
        let (editor, id, first) = (run.editor, run.id, run.first)
        let original = try XCTUnwrap(fileName(editor, id))
        let reopened = PhotoEditController.opening(id, current: first) { controller(editor, id, studio: SlowStudio()) }
        reopened.cancelVisit()
        try await Task.sleep(for: .milliseconds(1_200))
        XCTAssertNotEqual(fileName(editor, id), original, "the edit was kept with Done; this Cancel is not its")
    }
}
