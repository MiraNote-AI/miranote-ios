import MiraNoteKit
import XCTest
@testable import MiraNote

/// An AI photo edit whose result is let go at every point of what the user
/// does next (gate mocks): Done, Cancel, reopening the photo (also after
/// another photo, or after the Sticker scene rebuilt the canvas), B&W on
/// the reopened visit, deleting the photo, a canvas undo. Each case is one
/// order, named in the failure message.
@MainActor
final class PhotoEditOrderingTests: XCTestCase {
    private enum Step: String {
        case release, done, cancel, reopen, bw, delete, undo, otherPhoto, sceneTrip
    }

    func testAnAIEditLandingAnywhereInTheVisits() async throws {
        let scripts: [[Step]] = [
            [.done], [.cancel],
            [.done, .reopen, .bw, .done], [.done, .reopen, .cancel], [.done, .reopen, .bw, .cancel],
            [.done, .delete], [.done, .undo],
            [.done, .otherPhoto, .reopen, .cancel], [.done, .sceneTrip, .cancel]
        ]
        for script in scripts {
            for at in 0...script.count {
                var order = script
                order.insert(.release, at: at)
                try await check(order)
            }
        }
    }

    private func fileName(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        guard case .image(let ref) = editor.item(id)?.content else { return nil }
        return ref.fileName
    }

    private func filter(_ editor: CanvasViewModel, _ id: CanvasItem.ID) -> String? {
        guard case .image(let ref) = editor.item(id)?.content else { return nil }
        return ref.filterName
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func check(_ order: [Step]) async throws {
        let label = order.map(\.rawValue).joined(separator: " ")
        let store = ImageFileStore()
        let editor = CanvasViewModel(memory: Memory())
        let id = try XCTUnwrap(editor.addImages(
            [ImageRef(displayName: "photo", fileName: try store.save(MockImageStudioService.tinyPNG, id: UUID()))],
            around: CGPoint(x: 180, y: 200)
        ).first)
        let original = try XCTUnwrap(fileName(editor, id))
        let studio = GatedStudio()
        var editors = PhotoEditors()
        var reportsTo = 1, reported: [Int] = []
        func open(_ photo: CanvasItem.ID) -> PhotoEditController {
            let scene = reportsTo
            return editors.open(photo, onEdited: { reported.append(scene) }, onClose: {}, make: {
                PhotoEditController(itemID: photo, editor: editor, studio: studio,
                                    onEdited: { reported.append(scene) }, onClose: {})
            })
        }

        // The first visit runs an AI edit.
        var visit = open(id)
        visit.tap(.ai)
        visit.prompt = "make it autumn"
        visit.runComposer()
        let asked = await eventually { studio.stylizeCalls.count == 1 }
        XCTAssertTrue(asked, "\(label): the AI edit never reached the studio")

        var cancelledBeforeRelease = false, goneBeforeRelease = false, undoneAfterRelease = false
        var released = false, bwKept = false, bwPending = false, releasedAfterTrip = false
        for (index, step) in order.enumerated() {
            switch step {
            case .release:
                studio.stylizeCalls.releaseNext(.success(MockImageStudioService.tinyPNG + Data([1])))
                studio.describeCalls.releaseNext(.success("an autumn street"))
                try await Task.sleep(for: .milliseconds(50))
                released = true
                releasedAfterTrip = reportsTo == 2
            case .done:
                editors.close(id)
                if bwPending { bwKept = true }
            case .cancel:
                // The visit that runs the edit, cancelled, drops it (landed
                // or not: it is that visit's own); a later visit's Cancel
                // never takes back an edit kept with Done.
                if !order[..<index].contains(.done) { cancelledBeforeRelease = true }
                visit.cancelVisit()
                editors.close(id)
                bwPending = false
            case .reopen:
                visit = open(id)
            case .bw:
                visit.tap(.bw)
                bwPending = filter(editor, id) == "bw"
            case .delete:
                editor.delete(itemID: id)
                editors.dropDeleted(on: editor)
                if !released { goneBeforeRelease = true }
            case .undo:
                editor.undo()
                editors.dropDeleted(on: editor)
                if released { undoneAfterRelease = true } else { goneBeforeRelease = true }
            case .otherPhoto:
                let other = try XCTUnwrap(editor.addImages(
                    [ImageRef(displayName: "B", fileName: try store.save(MockImageStudioService.tinyPNG, id: UUID()))],
                    around: CGPoint(x: 180, y: 500)
                ).first)
                _ = open(other)
                editors.close(other)
            case .sceneTrip:
                // The Sticker scene rebuilt the canvas: the flow's editors
                // remain, and the photo is opened by the new scene.
                reportsTo = 2
                visit = open(id)
            }
        }
        studio.releaseAll()
        try await Task.sleep(for: .milliseconds(50))

        let kept = released && !cancelledBeforeRelease && !goneBeforeRelease && !undoneAfterRelease
        let deleted = order.contains(.delete) || (order.contains(.undo) && goneBeforeRelease)
        XCTAssertEqual(editor.item(id) == nil, deleted, "\(label): the photo")
        if !deleted {
            XCTAssertEqual(fileName(editor, id) != original, kept, "\(label): the AI edit landed or not")
            XCTAssertEqual(filter(editor, id) == "bw", bwKept, "\(label): this visit's B&W")
        }
        XCTAssertFalse(editors[id]?.working ?? false, "\(label): an editor still working with nothing held")
        if kept, releasedAfterTrip {
            XCTAssertEqual(reported.last, 2, "\(label): the landed edit reported to the gone scene")
        }
    }
}
