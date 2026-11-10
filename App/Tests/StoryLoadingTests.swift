import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// Loading a push's story (handoff 7.6, D4): a photo that never arrives
/// (a stalled iCloud download) is skipped at a limit, the story plays once
/// three photos are ready, and with fewer it closes quietly to Home.
final class StoryLoadingTests: XCTestCase {
    /// Every photo at once, but `stalled` ones only after a long wait.
    private struct Photos: TriggerPhotoProviding {
        let stalled: Set<String>

        func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage? {
            if stalled.contains(id) { try? await Task.sleep(for: .seconds(30)) }
            return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
        }

        func existing(_ ids: [String]) async -> Set<String> { Set(ids) }
    }

    private func memory() -> TriggerMemory {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let photos = ["P1", "P2", "P3", "P4"].enumerated().map { index, id in
            TriggerMemory.Photo(id: id, takenAt: start.addingTimeInterval(Double(index) * 60), isPeak: id == "P1")
        }
        return TriggerMemory(
            id: "m", date: "2025-10-09", daypart: .afternoon,
            push: .init(title: "t", body: "b", coverPhotoId: "P1"),
            story: .init(firstFrameLabel: "f", photos: photos),
            ending: .init(factLine: "f", detail: "",
                          questions: [.init(text: "q", type: "one_word", source: "fallback_B1")], ctaLabel: "c"))
    }

    private let photoIds = ["P1": "a", "P2": "b", "P3": "c", "P4": "d"]

    func testStalledPhotoIsSkippedAtTheLimit() async {
        let started = Date()
        var loaded: [String] = []
        for await photo in StoryPhoto.stream(memory(), photoIds: photoIds, from: Photos(stalled: ["b"]),
                                             within: 0.3) {
            loaded.append(photo.id)
        }
        XCTAssertEqual(loaded, ["P1", "P3", "P4"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the wait ends at the limit")
    }

    func testLimitIsAboutTenSeconds() {
        XCTAssertLessThanOrEqual(StoryPhoto.timeLimit, 10)
        XCTAssertGreaterThanOrEqual(StoryPhoto.timeLimit, 5)
    }

    func testStoryWaitsForThreePhotos() {
        XCTAssertEqual(StoryStart.decide(ready: 0, allTried: false), .wait)
        XCTAssertEqual(StoryStart.decide(ready: 1, allTried: false), .wait)
        XCTAssertEqual(StoryStart.decide(ready: 2, allTried: false), .wait)
        XCTAssertEqual(StoryStart.decide(ready: 3, allTried: false), .play)
        XCTAssertEqual(StoryStart.decide(ready: 3, allTried: true), .play)
    }

    /// Fewer than three could be read: Home, quietly -- no error to dismiss.
    func testFewerThanThreeLeaveQuietly() {
        XCTAssertEqual(StoryStart.decide(ready: 0, allTried: true), .leave)
        XCTAssertEqual(StoryStart.decide(ready: 2, allTried: true), .leave)
    }
}
