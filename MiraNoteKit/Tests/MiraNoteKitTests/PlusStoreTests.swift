import XCTest
@testable import MiraNoteKit

/// What `PlusStore` does with the server's answer, without StoreKit: its
/// tests skip on iOS 26.3 and later (PlusStoreKitTests).
@MainActor
final class PlusStoreTests: XCTestCase {
    private func settled(syncError: Error?) async -> (steps: [String], refused: PlusError?) {
        var steps: [String] = []
        let refused = await PlusStore.settle(
            sync: {
                steps.append("sync")
                if let syncError { throw syncError }
            },
            finish: { steps.append("finish") }
        )
        return (steps, refused)
    }

    func testAPurchaseAnotherAccountOwnsIsFinishedThenSaysSo() async {
        let (steps, refused) = await settled(syncError: PlusError.ownedByAnotherAccount)
        XCTAssertEqual(steps, ["sync", "finish"], "Apple has charged: finished whatever the server says")
        XCTAssertEqual(refused, .ownedByAnotherAccount)
    }

    func testAPurchaseTheServerDidNotHearOfIsFinishedQuietly() async {
        for error in [BackendError.unreachable, .timedOut, .answerLost, .server(status: 502, detail: nil)] {
            let (steps, refused) = await settled(syncError: error)
            XCTAssertEqual(steps, ["sync", "finish"], "\(error)")
            XCTAssertNil(refused, "the launch sync and Restore send it again: \(error)")
        }
    }

    func testAPurchaseTheServerTookIsFinished() async {
        let (steps, refused) = await settled(syncError: nil)
        XCTAssertEqual(steps, ["sync", "finish"])
        XCTAssertNil(refused)
    }
}
