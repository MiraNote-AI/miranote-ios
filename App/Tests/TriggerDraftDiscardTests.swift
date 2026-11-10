import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// A push draft that is not kept leaves nothing behind: the photo copies
/// its button saved are deleted -- only those.
final class TriggerDraftDiscardTests: XCTestCase {
    private struct Photos: TriggerPhotoProviding {
        func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage? {
            UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
            }
        }

        func existing(_ ids: [String]) async -> Set<String> { Set(ids) }
    }

    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func memory() -> TriggerMemory {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let photos = ["P1", "P2", "P3"].enumerated().map { index, id in
            TriggerMemory.Photo(id: id, takenAt: start.addingTimeInterval(Double(index) * 60), isPeak: id == "P1")
        }
        return TriggerMemory(
            id: "m", date: "2025-10-09", daypart: .afternoon,
            push: .init(title: "t", body: "b", coverPhotoId: "P1"),
            story: .init(firstFrameLabel: "f", photos: photos),
            ending: .init(factLine: "f", detail: "",
                          questions: [.init(text: "q", type: "one_word", source: "fallback_B1")], ctaLabel: "c"))
    }

    private func fileNames(_ page: Memory) -> [String] {
        page.items.compactMap { item in
            if case .image(let ref) = item.content { return ref.fileName }
            return nil
        }
    }

    func testDiscardDeletesTheDraftsPhotosOnly() async throws {
        let store = ImageFileStore(directory: folder)
        let other = try store.save(Data([1, 2, 3]), id: UUID())
        let draft = await TriggerDraftMaker.make(memory(), photoIds: ["P1": "a", "P2": "b", "P3": "c"],
                                                 photos: Photos(), store: store)
        let files = fileNames(draft.page)
        XCTAssertEqual(files.count, 3)
        XCTAssertTrue(files.allSatisfy(store.exists))

        TriggerDraftMaker.discard(draft.page, store: store)
        XCTAssertFalse(files.contains(where: store.exists), "the draft's photo copies are gone")
        XCTAssertTrue(store.exists(fileName: other), "another page's image stays")
    }
}
