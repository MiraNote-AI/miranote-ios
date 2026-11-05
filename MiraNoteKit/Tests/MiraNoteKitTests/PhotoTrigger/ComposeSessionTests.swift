import XCTest
@testable import MiraNoteKit

/// One group's round trip on the debug page (`ComposeSession`), on the fake
/// client: how its polls end.
final class ComposeSessionTests: XCTestCase {
    private let client = FakeClient()
    private let date = "2026-10-18"

    /// The session's failure, or nil when a memory came back.
    private func failure() async -> TriggerFailure? {
        let photos = (1...3).map {
            ComposeMeta.Photo(id: "P\($0)", takenAt: "2026-10-18T1\($0):00:00-05:00", labels: [], faces: 0,
                              favorite: false, edited: false, represents: 1)
        }
        let meta = ComposeMeta(groupKey: "g", date: date, weekday: 7, startTime: "11:00", endTime: "13:00",
                               place: nil, rawCount: 3, coversAll: true, recentQuestionTypes: [], bucket: "event",
                               tz: "America/Chicago", photos: photos)
        let session = ComposeSession(library: FakeLibrary(now: .now, groups: []), client: client, sleep: { _ in })
        switch await session.run(meta, photoIds: ["P1": "a", "P2": "b", "P3": "c"]) {
        case .success: return nil
        case .failure(let box):
            if case .stop(let failure) = box.attempt { return failure }
            return .backend("not a stop")
        }
    }

    func testPollRetriesAGatewayErrorOrANonJSONBody() async {
        client.pollErrors = [.server(502), .server(200)]
        let failure = await failure()
        XCTAssertNil(failure)
    }

    func testThreeServerErrorsInARowStopThePoll() async {
        client.pollErrors = [.server(500), .server(503), .server(502)]
        let failure = await failure()
        XCTAssertEqual(failure, .backend("HTTP 502"))
    }

    /// A failed job with no message shows its reason, as the scheduler does.
    func testFailedJobWithoutAMessageShowsItsReason() async {
        client.failedMessage = ""
        client.scripts[date] = [.failed("model_error")]
        let failure = await failure()
        XCTAssertEqual(failure, .backend("model_error"))
    }
}
