import XCTest
@testable import MiraNoteKit

// A restyle Mira asked for on the canvas: when her handle does not
// resolve, the selected photo -- else the only photo -- is what the
// user meant; several photos with no clear target stay a calm clarify.
@MainActor
final class MiraPhotoRestyleTurnTests: XCTestCase {
    private func boardWithPhoto(pixels: Bool = true) -> (CanvasViewModel, ImageFileStore) {
        let store = ImageFileStore()
        let name = pixels
            ? ((try? store.save(MockImageStudioService.tinyPNG, id: UUID())) ?? "")
            : ""
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: name, summary: "a grey bowl")),
            position: CGPoint(x: 180, y: 300),
            size: CGSize(width: 280, height: 200)
        )
        let model = CanvasViewModel(memory: Memory(items: [photo]))
        model.canvasWidth = MiraNoteConfig.pageWidth
        return (model, store)
    }

    private func coordinator(
        _ chat: ScriptedChat, store: ImageFileStore
    ) -> MiraCanvasCoordinator {
        MiraCanvasCoordinator(
            text: ScriptedText(), chat: chat,
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: MockImageStudioService(), imageStore: store
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

    func testARestyleNamingNothingWithSeveralPhotosAsksRatherThanGuessing() async {
        var chat = ScriptedChat()
        chat.reply = "Done."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p9", instruction: "warmer")
        let (board, store) = boardWithPhoto()
        _ = board.addImages(
            [ImageRef(displayName: "d2", fileName: "")],
            around: CGPoint(x: 180, y: 620))
        let mira = coordinator(chat, store: store)

        mira.ask("warm that up", editor: board)
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure(let failure) = mira.phase else {
            return XCTFail("expected a clarify card")
        }
        XCTAssertEqual(failure.kind, .clarify)
    }

    func testARestyleWithAWrongHandleStillFindsTheOnlyPhoto() async {
        var chat = ScriptedChat()
        chat.reply = "Warming it up."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p9", instruction: "warmer")
        let (board, store) = boardWithPhoto()
        let mira = coordinator(chat, store: store)

        mira.ask("warm the photo", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        guard case .receipt(let receipt) = mira.phase else {
            return XCTFail("the only photo is what the user meant")
        }
        XCTAssertEqual(receipt.changed, "Restyled the photo.")
    }

    func testARestyleWithAWrongHandlePrefersTheSelectedPhoto() async {
        var chat = ScriptedChat()
        chat.reply = "Warming it up."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p9", instruction: "warmer")
        let (board, store) = boardWithPhoto()
        guard case .image(let firstBefore) = board.items[0].content else {
            return XCTFail("the board starts with one photo")
        }
        let secondName = (try? store.save(MockImageStudioService.tinyPNG, id: UUID())) ?? ""
        let second = board.addImages(
            [ImageRef(displayName: "d2", fileName: secondName)],
            around: CGPoint(x: 180, y: 620)).first!
        board.select(second)
        let mira = coordinator(chat, store: store)

        mira.ask("warm that one", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        guard case .receipt(let receipt) = mira.phase else {
            return XCTFail("the selected photo is what the user meant")
        }
        XCTAssertEqual(receipt.changed, "Restyled the photo.")
        guard case .image(let firstAfter) = board.items[0].content,
              case .image(let secondRef) = board.item(second)?.content else {
            return XCTFail("both photos must still be photos")
        }
        XCTAssertEqual(firstAfter.fileName, firstBefore.fileName,
                       "the unselected photo keeps its pixels")
        XCTAssertNotEqual(secondRef.fileName, secondName,
                          "the selected photo carries freshly saved pixels")
    }
}
