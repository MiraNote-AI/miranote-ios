import XCTest
@testable import MiraNoteKit

/// One group's round trip on the debug page (`ComposeSession`), on the fake
/// client: how its polls end.
final class ComposeSessionTests: XCTestCase {
    private let client = FakeClient()
    private let date = "2026-10-18"

    /// The session's failure, or nil when a memory came back.
    private func failure(on client: ComposeClient? = nil) async -> TriggerFailure? {
        let photos = (1...3).map {
            ComposeMeta.Photo(id: "P\($0)", takenAt: "2026-10-18T1\($0):00:00-05:00", labels: [], faces: 0,
                              favorite: false, edited: false, represents: 1)
        }
        let meta = ComposeMeta(groupKey: "g", date: date, weekday: 7, startTime: "11:00", endTime: "13:00",
                               place: nil, rawCount: 3, coversAll: true, recentQuestionTypes: [], bucket: "event",
                               tz: "America/Chicago", photos: photos)
        let session = ComposeSession(library: FakeLibrary(now: .now, groups: []), client: client ?? self.client,
                                     sleep: { _ in })
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

    /// A sign-in the server refused even after a renewal ends there (#231):
    /// the entry says the writer was signed out, not that the backend is
    /// out of reach.
    func testAnEndedSignInStopsAsSignedOut() async {
        let failure = await failure(on: SignedOutClient())
        XCTAssertNotEqual(failure, .backendUnreachable)
        XCTAssertEqual(failure, .signedOut)
        XCTAssertEqual(PushScheduler.describe(.stop(.signedOut)), "signedOut", "the ledger's word for it")
    }
}

/// Every request fails as `HTTPClient` fails it once a renewed token is
/// refused too: the sign-in has ended.
private struct SignedOutClient: ComposeClient {
    func submit(_ meta: ComposeMeta, photos: [(id: String, jpeg: Data)]) async throws -> String {
        throw AccountError.signedOut
    }

    func poll(_ jobId: String) async throws -> ComposeJobStatus { throw AccountError.signedOut }

    func pollMany(_ jobIds: [String]) async throws -> [String: ComposeJobStatus] { throw AccountError.signedOut }
}
