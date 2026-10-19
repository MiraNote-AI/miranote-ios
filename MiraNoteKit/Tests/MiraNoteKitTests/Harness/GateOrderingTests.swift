import XCTest
@testable import MiraNoteKit

/// Async results released at every point of a user's flow (gate mocks):
/// each case is one interleaving, named in the failure message.
@MainActor
final class GateOrderingTests: XCTestCase {
    // MARK: Mira's title vs a writing session

    private enum Step: String, Equatable {
        case ask, land, start, type, done, cancel, undo
    }

    /// Every order of: Mira asked for a title and her reply let go, and the
    /// user writing in the block below (start, type, then Done, Cancel or
    /// Undo). Whatever the order: the title and the block never overlap;
    /// Cancel takes back only the words; Undo takes back the newest single
    /// thing -- the words typed or the title -- never both; Done keeps both.
    func testATitleLandingAnywhereInAWritingSession() async throws {
        for end in [Step.done, .cancel, .undo] {
            let user: [Step] = [.start, .type, end]
            for askAt in 0...user.count {
                for landAt in askAt...user.count {
                    var order = user
                    order.insert(.land, at: landAt)
                    order.insert(.ask, at: askAt)
                    try await checkTitle(order)
                }
            }
        }
    }

    private func checkTitle(_ order: [Step]) async throws {
        let label = order.map(\.rawValue).joined(separator: " ")
        let block = CanvasItem(content: .text(TextBlock(text: "lunch")), position: CGPoint(x: 150, y: 70),
                               size: CGSize(width: 240, height: 60))
        let photo = CanvasItem(content: .image(ImageRef(displayName: "p")), position: CGPoint(x: 150, y: 220),
                               size: CGSize(width: 240, height: 200), zIndex: 1)
        let editor = CanvasViewModel(memory: Memory(items: [block, photo]))
        editor.canvasWidth = 390
        let chat = GatedChat()
        let mira = MiraCanvasCoordinator(text: ScriptedText(), chat: chat, workingDelay: .milliseconds(1),
                                         timeout: .seconds(5))
        var typedAt: Int?, landedAt: Int?
        for (index, step) in order.enumerated() {
            let changes = editor.changeCount
            switch step {
            case .ask:
                mira.ask("add a soft title", editor: editor)
                let asked = await eventually { chat.calls.count == 1 }
                XCTAssertTrue(asked, "\(label): the title turn never reached the chat")
            case .land:
                chat.calls.releaseNext(.success(ChatReply(text: "A quiet lunch", sessionID: "s")))
                let landed = await eventually { !mira.isWorking }
                XCTAssertTrue(landed, "\(label): the title never landed")
                if editor.items.count == 3 { landedAt = index }
            case .start:
                editor.startEditingText(block.id)
            case .type:
                guard editor.editingTextItemID == block.id else { break }
                editor.setText(itemID: block.id, to: "lunch with Sam and Jo by the river")
                editor.autosizeTextHeight(itemID: block.id, to: 90)
                typedAt = index
            case .done:
                editor.endEditingText()
            case .cancel:
                editor.cancelEditingText()
            case .undo:
                editor.undo()
            }
            // The scene: a recorded change moves a waiting receipt on.
            if editor.changeCount != changes { mira.canvasDidChange(editor) }
        }
        chat.calls.releaseAll(.failure(GateError()))

        let title = editor.items.first { item in
            if case .text(let words) = item.content { return words.pointSize == 30 }
            return false
        }
        guard case .text(let words) = editor.item(block.id)?.content else {
            return XCTFail("\(label): the block is gone")
        }
        let typed = words.text != "lunch"
        if let title, let now = editor.item(block.id) {
            XCTAssertFalse(Self.frame(title).intersects(Self.frame(now).insetBy(dx: 0.5, dy: 0.5)),
                           "\(label): the title and the block overlap")
        }
        guard let endAt = order.firstIndex(where: { [.done, .cancel, .undo].contains($0) }) else { return }
        switch order[endAt] {
        case .done:
            XCTAssertEqual(typed, typedAt != nil, "\(label): Done lost the words")
            XCTAssertEqual(title != nil, landedAt != nil, "\(label): Done lost the title")
        case .cancel:
            XCTAssertFalse(typed, "\(label): Cancel kept the words")
            XCTAssertEqual(title != nil, landedAt != nil, "\(label): Cancel took the title too")
        default:
            // Undo: the newest single thing before it, never both; a title
            // landing after the undo stays.
            let newest = [typedAt, landedAt].compactMap { $0 }.filter { $0 < endAt }.max()
            XCTAssertEqual(typed, typedAt != nil && newest != typedAt, "\(label): Undo and the words")
            let titleStays = landedAt.map { $0 > endAt || newest != $0 } ?? false
            XCTAssertEqual(title != nil, titleStays, "\(label): Undo and the title")
        }
    }

    // MARK: The Background tool's Apply

    /// Owner, TestFlight 1.0(5): "Apply to this page" + Apply did nothing
    /// visible -- the painting waited as two thumbnails in a card after the
    /// sheet had closed. Now Apply's painting lands on the page when it
    /// comes back, however long it takes, and Revert takes it back. A
    /// background asked for in the chat still offers the two to pick from.
    func testApplyToThisPageWearsThePaintingWhenItLands() async throws {
        let editor = CanvasViewModel(memory: Memory())
        let studio = GatedStudio()
        let mira = MiraCanvasCoordinator(text: ScriptedText(), chat: GatedChat(), workingDelay: .milliseconds(1),
                                         imageStudio: studio)
        mira.askBackground("a soft sunset glow", editor: editor)
        let asked = await eventually { studio.generateCalls.count == 1 }
        XCTAssertTrue(asked, "Apply never asked for a painting")
        XCTAssertEqual(editor.memory.backgroundFileName, "", "nothing on the page before the painting is back")

        studio.generateCalls.releaseNext(.success([Data([1]), Data([2])]))
        let landed = await eventually { !editor.memory.backgroundFileName.isEmpty }
        XCTAssertTrue(landed, "the page wears no painting after Apply")
        XCTAssertEqual(editor.memory.backgroundSummary, "a soft sunset glow")
        XCTAssertTrue(mira.receiptCanRevert)
        mira.revert(editor: editor)
        XCTAssertEqual(editor.memory.backgroundFileName, "", "Revert takes the painting back")

        mira.askSuggestion(MiraCanvasCoordinator.changeBackgroundChip, editor: editor)
        let chatAsked = await eventually { studio.generateCalls.count == 2 }
        XCTAssertTrue(chatAsked)
        studio.generateCalls.releaseNext(.success([Data([3]), Data([4])]))
        let offered = await eventually { if case .imageChoices = mira.phase { return true } else { return false } }
        XCTAssertTrue(offered, "a chat background ask still offers two to pick from")
        XCTAssertEqual(editor.memory.backgroundFileName, "")
    }

    /// Apply's painting fails (offline, the image timeout) and Try again
    /// paints again: that painting lands on the page too, never as the two
    /// to pick from that a chat background offers.
    func testTryAgainAfterAFailedApplyWearsThePainting() async throws {
        let editor = CanvasViewModel(memory: Memory())
        let studio = GatedStudio()
        let mira = MiraCanvasCoordinator(text: ScriptedText(), chat: GatedChat(), workingDelay: .milliseconds(1),
                                         imageStudio: studio)
        mira.askBackground("a soft sunset glow", editor: editor)
        let asked = await eventually { studio.generateCalls.count == 1 }
        XCTAssertTrue(asked, "Apply never asked for a painting")
        studio.generateCalls.releaseNext(.failure(GateError()))
        let failed = await eventually { if case .failure = mira.phase { return true } else { return false } }
        XCTAssertTrue(failed, "the painting failed")

        mira.retry(editor: editor)
        let askedAgain = await eventually { studio.generateCalls.count == 2 }
        XCTAssertTrue(askedAgain, "Try again never asked for a painting")
        studio.generateCalls.releaseNext(.success([Data([1]), Data([2])]))
        let landed = await eventually { !editor.memory.backgroundFileName.isEmpty }
        XCTAssertTrue(landed, "Try again's painting waits to be picked instead of landing")
    }

    private static func frame(_ item: CanvasItem) -> CGRect {
        CGRect(x: item.position.x - item.size.width / 2, y: item.position.y - item.size.height / 2,
               width: item.size.width, height: item.size.height)
    }
}
