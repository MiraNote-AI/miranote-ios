import XCTest
@testable import MiraNoteKit

@MainActor
final class MiraCanvasTurnTests: XCTestCase {
    private func editor(extraBlocks: Int = 0) -> CanvasViewModel {
        var items = [CanvasItem(
            content: .text(TextBlock(text: "Noodle shop", pointSize: 30)),
            position: CGPoint(x: 180, y: 300),
            size: CGSize(width: 304, height: 44)
        )]
        for index in 0..<extraBlocks {
            items.append(CanvasItem(
                content: .text(TextBlock(text: "block \(index)", pointSize: 15)),
                position: CGPoint(x: 180, y: CGFloat(index) * 90 + 500),
                size: CGSize(width: 304, height: 40)
            ))
        }
        let model = CanvasViewModel(memory: Memory(items: items))
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
        XCTAssertEqual(item.position.x - item.size.width / 2, 28, accuracy: 0.5)

        board.undo()
        XCTAssertEqual(board.items[0].position.y, 300, accuracy: 0.5)
        XCTAssertFalse(board.canUndo, "one turn, one undo step")
    }

    func testTheReceiptNamesWhatChanged() async {
        var chat = ScriptedChat()
        chat.pageEdits = [ElementChange(handle: "t1", x: 28, y: 24)]
        let mira = coordinator(chat)

        mira.ask("move it up", editor: editor())
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        guard case .receipt(let receipt) = mira.phase else { return XCTFail("expected a receipt") }
        XCTAssertEqual(receipt.changed, "Moved the title.")
    }

    func testTheCanvasTurnSendsAPageMapNotAFlatNote() async {
        var chat = ScriptedChat()
        chat.reply = "Sure."
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("how does this page look", editor: board)
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        let pages = await chat.recorder.pages
        XCTAssertEqual(pages.first??.map.width, MiraNoteConfig.pageWidth,
                       "the page is a fixed-width column, not the device width")
        XCTAssertEqual(pages.first??.map.elements.first?.handle, "t1")
        let notes = await chat.recorder.notes
        XCTAssertEqual(notes.first, [])
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
        XCTAssertFalse(board.canUndo, "a change that never landed leaves no undo step")
    }

    func testTidyOnASingleElementPageAsksRatherThanPretending() async {
        let mira = coordinator(ScriptedChat())

        mira.ask("tidy this page up", editor: editor())
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure(let failure) = mira.phase else {
            return XCTFail("expected a clarify card")
        }
        XCTAssertEqual(failure.kind, .clarify)
    }

    func testTidyOnAFullPageGoesToTheModel() async {
        var chat = ScriptedChat()
        chat.pageEdits = [
            ElementChange(handle: "t1", x: 28, y: 28),
            ElementChange(handle: "t2", x: 28, y: 120),
            ElementChange(handle: "t3", x: 28, y: 200)
        ]
        let board = editor(extraBlocks: 2)
        let mira = coordinator(chat)

        mira.ask("tidy this page up", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        guard case .receipt(let receipt) = mira.phase else { return XCTFail("expected a receipt") }
        XCTAssertEqual(receipt.changed, "Rearranged the page.")
        board.undo()
        XCTAssertFalse(board.canUndo, "a whole-page rearrange is still one step")
    }

    func testTheRenderedPageRidesAlongWhenTheClosureIsWired() async {
        var chat = ScriptedChat()
        chat.reply = "ok"
        let mira = coordinator(chat)
        mira.renderPage = { Data([0xFF, 0xD8, 0xFF]) }

        mira.ask("how does this look", editor: editor())
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        let pages = await chat.recorder.pages
        XCTAssertEqual(pages.first??.image?.count, 3)
    }

    func testNoRenderClosureIsNotAFailure() async {
        var chat = ScriptedChat()
        chat.reply = "ok"
        let mira = coordinator(chat)

        mira.ask("how does this look", editor: editor())
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        let pages = await chat.recorder.pages
        XCTAssertNil(pages.first??.image)
        guard case .reply = mira.phase else { return XCTFail("an unwired renderer is not a failure") }
    }

    func testAPlainAnswerIsStillJustAReply() async {
        var chat = ScriptedChat()
        chat.reply = "It looks calm to me."
        let board = editor()
        let mira = coordinator(chat)

        mira.ask("how does this page feel", editor: board)
        await waitUntil { if case .reply = mira.phase { return true }; return false }

        XCTAssertFalse(board.canUndo, "a reply must not touch the canvas")
    }

    // MARK: The keyword ladder must not steal sentences about an element

    func testMovingTheTitleIsNotAddingATitle() {
        let board = editor()
        let intent = MiraIntent.classify("move the title above the photo", editor: board)
        guard case .canvasTurn = intent else {
            return XCTFail("\"title\" is a noun here, not a request, got \(intent)")
        }
    }

    func testResizingTheTitleIsNotAddingATitle() {
        let intent = MiraIntent.classify("the title is too small", editor: editor())
        guard case .canvasTurn = intent else {
            return XCTFail("expected a canvas turn, got \(intent)")
        }
    }

    func testAskingForATitleStillWritesOne() {
        let intent = MiraIntent.classify("add a soft title", editor: editor())
        guard case .addTitle = intent else {
            return XCTFail("expected addTitle, got \(intent)")
        }
    }

    func testAChineseTitleAskGoesToTheCanvasTurn() {
        // jia-ge-biaoti. The title branch has always keyed on the literal
        // English word, so this has never reached it -- pinning today's
        // behaviour, not endorsing it (see the spec's follow-ups).
        let intent = MiraIntent.classify("\u{52A0}\u{4E2A}\u{6807}\u{9898}", editor: editor())
        guard case .canvasTurn = intent else {
            return XCTFail("expected a canvas turn, got \(intent)")
        }
    }

    // MARK: Slow image work, and life without a backend

    func testABackgroundRequestRunsAsAFreshStoppableTurn() async {
        var chat = ScriptedChat()
        chat.reply = "Painting a dusk sky."
        chat.backgroundRequest = .set(prompt: "a quiet dusk sky")
        let mira = coordinator(chat)

        mira.ask("change the background", editor: editor())
        // The chat turn settles, then the image work starts as its own
        // turn -- so Stop has something to cancel.
        await waitUntil { mira.isWorking }
        XCTAssertTrue(mira.isWorking, "the slow work must be a turn Stop can cancel")

        mira.stop()
        XCTAssertFalse(mira.isWorking)
        XCTAssertEqual(mira.refillPrompt, "change the background")
    }

    func testClearingTheBackgroundIsInstantAndUndoable() async {
        var chat = ScriptedChat()
        chat.reply = "Cleared."
        chat.backgroundRequest = .clear
        let board = editor()
        board.setBackground(fileName: "dusk.png")
        let mira = coordinator(chat)

        mira.ask("remove the background", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        XCTAssertTrue(board.memory.backgroundFileName.isEmpty)
        board.undo()
        XCTAssertEqual(board.memory.backgroundFileName, "dusk.png")
    }

    func testTidyFallsBackToLocalRearrangeWhenTheBackendIsDown() async {
        var chat = ScriptedChat()
        chat.error = BackendError.unreachable
        let board = editor(extraBlocks: 2)
        let before = board.items.map(\.position)
        let mira = coordinator(chat)

        mira.ask("tidy this page up", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        guard case .receipt(let receipt) = mira.phase else {
            return XCTFail("a deterministic local rearrange beats a failure card")
        }
        XCTAssertEqual(receipt.changed, "Tidied the layout.")
        XCTAssertNotEqual(board.items.map(\.position), before)
        board.undo()
        XCTAssertEqual(board.items.map(\.position), before)
    }

    func testANonLayoutAskStillFailsWhenTheBackendIsDown() async {
        var chat = ScriptedChat()
        chat.error = BackendError.unreachable
        let board = editor(extraBlocks: 2)
        let mira = coordinator(chat)

        mira.ask("how does this page look", editor: board)
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure = mira.phase else {
            return XCTFail("only layout asks have a local answer")
        }
        XCTAssertFalse(board.canUndo, "a failed turn leaves the canvas alone")
    }

    // MARK: Restyling a photo Mira can see

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

    func testARestyleRequestRunsAsAFreshStoppableTurn() async {
        var chat = ScriptedChat()
        chat.reply = "Warming it up."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p1", instruction: "warm golden light")
        let (board, store) = boardWithPhoto()
        let mira = MiraCanvasCoordinator(
            text: ScriptedText(), chat: chat,
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: MockImageStudioService(), imageStore: store
        )

        mira.ask("the photo feels too cold", editor: board)
        await waitUntil { if case .receipt = mira.phase { return true }; return false }

        guard case .receipt(let receipt) = mira.phase else {
            return XCTFail("a restyle lands like any other change")
        }
        XCTAssertEqual(receipt.changed, "Restyled the photo.")
        board.undo()
        XCTAssertFalse(board.canUndo, "one restyle, one undo step")
    }

    func testARestyleNamingNothingAsksRatherThanGuessing() async {
        var chat = ScriptedChat()
        chat.reply = "Done."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p9", instruction: "warmer")
        let (board, store) = boardWithPhoto()
        let mira = MiraCanvasCoordinator(
            text: ScriptedText(), chat: chat,
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: MockImageStudioService(), imageStore: store
        )

        mira.ask("warm that up", editor: board)
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure(let failure) = mira.phase else {
            return XCTFail("expected a clarify card")
        }
        XCTAssertEqual(failure.kind, .clarify)
    }

    func testARestyleOfAPhotoWithNoPixelsSaysSo() async {
        var chat = ScriptedChat()
        chat.reply = "Done."
        chat.photoRestyle = PhotoRestyleRequest(handle: "p1", instruction: "warmer")
        let (board, store) = boardWithPhoto(pixels: false)
        let mira = MiraCanvasCoordinator(
            text: ScriptedText(), chat: chat,
            workingDelay: .milliseconds(1), timeout: .seconds(5),
            receiptDismiss: .seconds(60),
            imageStudio: MockImageStudioService(), imageStore: store
        )

        mira.ask("warm the photo", editor: board)
        await waitUntil { if case .failure = mira.phase { return true }; return false }

        guard case .failure(let failure) = mira.phase else {
            return XCTFail("expected the missing-pixels clarify")
        }
        XCTAssertEqual(failure.kind, .clarify)
        XCTAssertTrue(failure.message.contains("no stored pixels"))
    }
}
