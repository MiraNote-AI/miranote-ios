import XCTest
@testable import MiraNoteKit

/// The AI services' account guard says why it answers 503 (miranote-api
/// #112, #118). A signed-in request reads that; any other 503 reads as
/// before.
@MainActor
final class AccountGuardMessageTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    nonisolated private static func answer(_ request: URLRequest, _ status: Int,
                                           _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    /// What a signed-in AI request fails with when answered `status` and `body`.
    private func failure(status: Int, body: String) async -> Error? {
        StubURLProtocol.handler = { Self.answer($0, status, body) }
        let tokens = AccountTokens(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1",
                                   accessExpiresAt: Date().addingTimeInterval(3600))
        let account = Account(store: InMemoryTokenStore(tokens), api: FakeAccountsAPI(), apple: FakeApple())
        var request = URLRequest(url: URL(string: "http://localhost:8001/expand")!)
        request.httpMethod = "POST"
        do {
            _ = try await HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "beta", userTokens: account)
                .send(request)
            return nil
        } catch {
            return error
        }
    }

    func testTheAccountsServiceDownSaysTryShortly() async {
        let body = #"{"reason": "accounts_unavailable", "detail": "sign-in service unavailable, try again shortly"}"#
        let error = await failure(status: 503, body: body)
        XCTAssertEqual(error?.localizedDescription,
                       "MiraNote's sign-in service isn't answering right now. Try again shortly.")
    }

    /// `resets_at` is the next UTC midnight, said in the phone's time.
    func testAPausedFeatureSaysWhenItIsBack() async throws {
        let body = #"{"reason": "service_paused", "feature": "chat", "resets_at": "2026-11-19T00:00:00+00:00","#
            + #" "detail": "this feature is paused for today, try again later"}"#
        let error = await failure(status: 503, body: body)
        XCTAssertTrue(error?.localizedDescription.hasPrefix("Mira has paused this for now. Try again after ") == true,
                      String(describing: error?.localizedDescription))

        for (zone, hour) in [("Asia/Shanghai", 8), ("America/Los_Angeles", 16)] {
            let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let back = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 11, day: hour < 12 ? 19 : 18, hour: hour)))
            let time = back.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                                       locale: AppSettings.shared.language.locale,
                                                       timeZone: timeZone))
            XCTAssertEqual(BackendError.guardMessage(status: 503, detail: body, timeZone: timeZone),
                           "Mira has paused this for now. Try again after \(time).", zone)
        }
    }

    func testAPausedFeatureWithFractionalSecondsOrNoTime() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let fractional = #"{"reason": "service_paused", "resets_at": "2026-11-19T00:00:00.250000+00:00"}"#
        XCTAssertEqual(BackendError.guardMessage(status: 503, detail: fractional, timeZone: zone),
                       BackendError.guardMessage(status: 503, detail: fractional.replacingOccurrences(
                           of: ".250000", with: ""), timeZone: zone))
        XCTAssertEqual(BackendError.guardMessage(status: 503, detail: #"{"reason": "service_paused"}"#),
                       "Mira has paused this for now. Try again later.")
    }

    /// Any other 503 keeps the image provider's words, as before.
    func testAnyOther503IsUnchanged() async {
        let before = BackendError.server(status: 503, detail: nil).localizedDescription
        for body in ["", #"{"detail": "quota"}"#, #"{"status": "error", "reason": "busy"}"#, "<html>503</html>"] {
            let error = await failure(status: 503, body: body)
            XCTAssertEqual(error?.localizedDescription, before, body)
        }
        XCTAssertTrue(before.hasPrefix("The image service has used up its quota"))
    }
}
