import MiraNoteKit
import XCTest
@testable import MiraNote

/// The story menu's "Fewer like this" names the push's bucket; with no
/// bucket to name it is not offered.
final class TriggerOpeningTests: XCTestCase {
    private func opening(bucketId: PushBucket?, bucket: String = "") -> TriggerOpening {
        let photos = ["P1", "P2", "P3"].map { TriggerMemory.Photo(id: $0, takenAt: .now, isPeak: $0 == "P1") }
        let memory = TriggerMemory(
            id: "m", date: "2026-10-18", daypart: .afternoon, bucket: bucket,
            push: .init(title: "t", body: "b", coverPhotoId: "P1"),
            story: .init(firstFrameLabel: "f", photos: photos),
            ending: .init(factLine: "f", detail: "",
                          questions: [.init(text: "q", type: "one_word", source: "fallback_B1")], ctaLabel: "c"))
        return TriggerOpening(pushId: "p", memory: memory, photoIds: [:], bucketId: bucketId)
    }

    func testABucketOffersFewer() {
        XCTAssertTrue(opening(bucketId: .food).allowsFewer)
    }

    func testOtherDoesNotOfferFewer() {
        XCTAssertFalse(opening(bucketId: .other).allowsFewer)
    }

    /// A phase-1 record: no bucket, so the choice would read `Fewer like ""`
    /// and the scheduler would ignore it.
    func testAnOldRecordWithoutABucketDoesNotOfferFewer() {
        XCTAssertFalse(opening(bucketId: nil).allowsFewer)
    }
}
