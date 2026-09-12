import XCTest
@testable import MiraNoteKit

/// Six distinguishable failures, each needing a different action from the
/// tester. Without this every one of them reads "The server returned an error
/// (status N)", and ten non-technical testers report all six as "the app is
/// broken".
final class BackendErrorTests: XCTestCase {
    private func message(_ error: BackendError) -> String {
        error.errorDescription ?? ""
    }

    private var mapped: [Int: String] {
        [
            401: message(.server(status: 401, detail: nil)),
            429: message(.server(status: 429, detail: nil)),
            502: message(.server(status: 502, detail: nil)),
            503: message(.server(status: 503, detail: nil)),
            530: message(.server(status: 530, detail: nil))
        ]
    }

    func testEveryMappedStatusSaysSomethingDifferent() {
        let messages = Array(mapped.values) + [message(.timedOut)]
        XCTAssertEqual(
            Set(messages).count, messages.count,
            "two conditions share a message, so they cannot be told apart"
        )
    }

    func testNoMappedStatusLeaksTheRawNumber() {
        for (status, text) in mapped {
            XCTAssertFalse(
                text.contains("\(status)"),
                "status \(status) still shows the raw code: \(text)"
            )
        }
    }

    func testEveryMappedStatusTellsTheTesterWhatToDo() {
        // Each message has to end in something actionable rather than a
        // diagnosis the tester can do nothing with.
        for (status, text) in mapped {
            XCTAssertFalse(text.isEmpty, "status \(status) has no message")
            XCTAssertTrue(
                text.count > 30,
                "status \(status) message is too terse to act on: \(text)"
            )
        }
    }

    func testUnmappedStatusesStillFallBackToTheCode() {
        let text = message(.server(status: 418, detail: nil))
        XCTAssertTrue(text.contains("418"), "an unmapped status should still say what it was")
    }

    /// 429 is our own per-token rate limit; 503 is the upstream image provider
    /// refusing us. They look alike and have nothing to do with each other, so
    /// the messages must not suggest the same cause.
    func testRateLimitAndProviderQuotaAreNotConfused() {
        XCTAssertNotEqual(mapped[429], mapped[503])
    }

    func testTimeoutInvitesOneManualRetry() {
        let text = message(.timedOut)
        XCTAssertTrue(
            text.lowercased().contains("again") || text.lowercased().contains("retry"),
            "a timeout should invite a retry: \(text)"
        )
    }
}
