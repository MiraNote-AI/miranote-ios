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

    func testAPurchaseTheServerRefusesIsFinishedThenSaysWhy() async {
        for error in [PlusError.ownedByAnotherAccount, .movedTooOften] {
            let (steps, refused) = await settled(syncError: error)
            XCTAssertEqual(steps, ["sync", "finish"], "Apple has charged: finished whatever the server says")
            XCTAssertEqual(refused, error)
        }
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

    // MARK: The server's refusals

    func testTheServerSaysWhoseChainItIs() {
        XCTAssertEqual(PlusError(syncFailure: BackendError.server(status: 403, detail: nil)), .ownedByAnotherAccount)
        XCTAssertEqual(PlusError(syncFailure: BackendError.server(status: 409, detail: nil)), .ownedByAnotherAccount)
    }

    /// miranote-api #113: a chain relinked within 30 days, or a third link
    /// in a day, is a 429 that says nothing about the beta's rate limit.
    func testTheRelinkLimitSaysThePurchaseMovedTooOften() {
        let detail = #"{"detail": "this purchase was moved recently"}"#
        let refused = PlusError(syncFailure: BackendError.server(status: 429, detail: detail))
        XCTAssertEqual(refused, .movedTooOften)
        XCTAssertEqual(refused?.localizedDescription,
                       "This purchase has moved between MiraNote accounts too often. Contact us to move it.")
    }

    func testOtherFailuresAreNotTheServersRefusal() {
        for error in [BackendError.unreachable, .answerLost, .server(status: 500, detail: nil)] {
            XCTAssertNil(PlusError(syncFailure: error), "\(error)")
        }
        XCTAssertNil(PlusError(syncFailure: AccountError.signedOut))
    }
}
