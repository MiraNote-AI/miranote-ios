import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// A push's cover that never arrives (a stalled iCloud download) must not
/// hold up scheduling: past the limit the push goes out without one.
final class TriggerCoverTimeoutTests: XCTestCase {
    private struct Photos: TriggerPhotoProviding {
        let delay: TimeInterval

        func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage? {
            try? await Task.sleep(for: .seconds(delay))
            return UIImage(systemName: "photo")
        }

        func existing(_ ids: [String]) async -> Set<String> { Set(ids) }
    }

    private func record() -> PushRecord {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let photos = ["P1", "P2", "P3"].enumerated().map { index, id in
            TriggerMemory.Photo(id: id, takenAt: start.addingTimeInterval(Double(index) * 60), isPeak: id == "P2")
        }
        let memory = TriggerMemory(
            id: "m", date: "2025-10-09", daypart: .afternoon,
            push: .init(title: "t", body: "b", coverPhotoId: "P2"),
            story: .init(firstFrameLabel: "f", photos: photos),
            ending: .init(factLine: "f", detail: "", question: "q", questionId: "B1", ctaLabel: "c"))
        return PushRecord(pushId: "p", memory: memory, photoIds: ["P1": "a", "P2": "b", "P3": "c"],
                          createdAt: start, rank: 1, score: 0.5, bucket: "food")
    }

    func testStalledCoverIsDroppedAtTheLimit() async {
        let started = Date()
        let image = await LivePushNotificationCenter.cover(of: record(), photos: Photos(delay: 30), within: 0.3)
        XCTAssertNil(image)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the wait ends at the limit")
    }

    func testQuickCoverIsUsed() async {
        let image = await LivePushNotificationCenter.cover(of: record(), photos: Photos(delay: 0), within: 5)
        XCTAssertNotNil(image)
    }

    func testLimitIsShort() {
        XCTAssertLessThanOrEqual(LivePushNotificationCenter.coverTimeout, 10)
    }
}
