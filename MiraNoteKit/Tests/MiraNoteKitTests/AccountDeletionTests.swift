import XCTest
@testable import MiraNoteKit

/// api #95 step 6: Delete account. Apple confirms first, `DELETE /me`
/// with its fresh code, our tokens forgotten once the server says
/// deleted, and every failure kept apart from success.
@MainActor
final class AccountDeletionTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func tokens(_ number: Int, expiresIn: TimeInterval = 3600) -> AccountTokens {
        AccountTokens(accessToken: "access-\(number)", refreshToken: "refresh-\(number)", userID: "user-1",
                      accessExpiresAt: clock.addingTimeInterval(expiresIn))
    }

    private func deletion(store: InMemoryTokenStore, api: FakeAccountsAPI,
                          apple: FakeApple = FakeApple()) -> (AccountDeletion, Account) {
        let account = Account(store: store, api: api, apple: apple, now: { [unowned self] in clock })
        return (AccountDeletion(account: account), account)
    }

    // MARK: Deleted

    func testDeleteSendsTheFreshCodeAndForgetsTheTokens() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        let (deletion, account) = deletion(store: store, api: api)
        XCTAssertEqual(deletion.state, .ready)

        await deletion.delete()

        XCTAssertEqual(deletion.state, .deleted(appleRevoked: true))
        XCTAssertEqual(api.deletes.map(\.accessToken), ["access-1"])
        XCTAssertEqual(api.deletes.map(\.authorizationCode), ["apple-code-1"])
        XCTAssertNil(store.load())
        XCTAssertFalse(account.isSignedIn)
        XCTAssertEqual(api.signOuts, [], "the server already ended every session")
    }

    func testAppleNotToldIsStillDeleted() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        api.deleteResult = .success(false)
        let (deletion, account) = deletion(store: store, api: api)
        await deletion.delete()
        XCTAssertEqual(deletion.state, .deleted(appleRevoked: false))
        XCTAssertNil(store.load())
        XCTAssertFalse(account.isSignedIn)
    }

    func testAnExpiringAccessTokenIsRefreshedBeforeTheDelete() async {
        let store = InMemoryTokenStore(tokens(1, expiresIn: 10))
        let api = FakeAccountsAPI(refreshResults: [.success(tokens(2))])
        let (deletion, _) = deletion(store: store, api: api)
        await deletion.delete()
        XCTAssertEqual(api.refreshes, ["refresh-1"])
        XCTAssertEqual(api.deletes.map(\.accessToken), ["access-2"])
        XCTAssertEqual(deletion.state, .deleted(appleRevoked: true))
        XCTAssertNil(store.load(), "the refreshed pair is forgotten too")
    }

    func testDeletedDoesNotDeleteAgain() async {
        let api = FakeAccountsAPI()
        let (deletion, _) = deletion(store: InMemoryTokenStore(tokens(1)), api: api)
        await deletion.delete()
        await deletion.delete()
        XCTAssertEqual(api.deletes.count, 1)
    }

    // MARK: Not deleted

    func testClosingApplesSheetGoesBackAndSendsNothing() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        let (deletion, account) = deletion(store: store, api: api,
                                           apple: FakeApple(error: AppleSignInError.cancelled))
        await deletion.delete()
        XCTAssertEqual(deletion.state, .ready)
        XCTAssertEqual(api.deletes.count, 0)
        XCTAssertEqual(store.load(), tokens(1))
        XCTAssertTrue(account.isSignedIn)
    }

    func testAFailedAppleSheetSendsNothing() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        let (deletion, account) = deletion(store: store, api: api,
                                           apple: FakeApple(error: AppleSignInError.noAuthorizationCode))
        await deletion.delete()
        XCTAssertEqual(deletion.state, .failed(.apple))
        XCTAssertEqual(api.deletes.count, 0)
        XCTAssertTrue(account.isSignedIn)
    }

    func testOfflineKeepsTheAccountAndTryAgainAsksAppleAgain() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        api.deleteResult = .failure(BackendError.unreachable)
        let (deletion, account) = deletion(store: store, api: api)

        await deletion.delete()
        XCTAssertEqual(deletion.state, .failed(.offline))
        XCTAssertEqual(store.load(), tokens(1))
        XCTAssertTrue(account.isSignedIn)

        api.deleteResult = .success(true)
        await deletion.delete()
        XCTAssertEqual(deletion.state, .deleted(appleRevoked: true))
        XCTAssertEqual(api.deletes.map(\.authorizationCode), ["apple-code-1", "apple-code-2"],
                       "a code is single-use: each try gets a new one")
    }

    func testATimeoutKeepsTheTokens() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        api.deleteResult = .failure(BackendError.timedOut)
        let (deletion, account) = deletion(store: store, api: api)
        await deletion.delete()
        XCTAssertEqual(deletion.state, .failed(.timedOut))
        XCTAssertTrue(account.isSignedIn)
    }

    func testAnEndedSignInForgetsTheDeadTokens() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        api.deleteResult = .failure(BackendError.server(status: 401, detail: nil))
        let (deletion, account) = deletion(store: store, api: api)
        await deletion.delete()
        XCTAssertEqual(deletion.state, .failed(.signedOut))
        XCTAssertNil(store.load())
        XCTAssertFalse(account.isSignedIn)
    }

    func testAServerErrorKeepsTheTokens() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        api.deleteResult = .failure(BackendError.server(status: 500, detail: nil))
        let (deletion, account) = deletion(store: store, api: api)
        await deletion.delete()
        XCTAssertEqual(deletion.state, .failed(.server))
        XCTAssertEqual(store.load(), tokens(1))
        XCTAssertTrue(account.isSignedIn)
    }

    func testEveryFailureSaysSomething() {
        for failure in [AccountDeletion.Failure.offline, .timedOut, .signedOut, .apple, .server] {
            XCTAssertFalse(failure.localizedDescription.isEmpty)
        }
    }

    // MARK: The live API

    private func liveAPI(status: Int, body: String) -> (LiveAccountsAPI, () -> URLRequest?) {
        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let api = LiveAccountsAPI(baseURL: URL(string: "https://accounts.test")!,
                                  client: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: nil,
                                                     userTokens: nil))
        return (api, { seen })
    }

    func testLiveDeleteSendsTheCodeWithOurToken() async throws {
        let (api, seen) = liveAPI(status: 200, body: #"{"deleted": true, "apple_revoked": true}"#)
        defer { StubURLProtocol.handler = nil }

        let appleRevoked = try await api.deleteAccount(accessToken: "access-1", authorizationCode: "code-1")

        XCTAssertTrue(appleRevoked)
        let request = try XCTUnwrap(seen())
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.capturedBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body as? [String: String], ["authorization_code": "code-1"])
    }

    func testLiveDeleteReadsDeletedFromA502Or503() async throws {
        defer { StubURLProtocol.handler = nil }
        for status in [502, 503] {
            let (api, _) = liveAPI(status: status,
                                   body: #"{"deleted": true, "apple_revoked": false, "detail": "x"}"#)
            let appleRevoked = try await api.deleteAccount(accessToken: "a", authorizationCode: "c")
            XCTAssertFalse(appleRevoked, "\(status): deleted, Apple not told")
        }
    }

    func testLiveDeleteThrowsWhenNothingWasDeleted() async {
        defer { StubURLProtocol.handler = nil }
        for (status, body) in [(422, #"{"detail": "missing"}"#), (502, "Bad Gateway"), (401, "")] {
            let (api, _) = liveAPI(status: status, body: body)
            do {
                _ = try await api.deleteAccount(accessToken: "a", authorizationCode: "c")
                XCTFail("\(status): expected an error")
            } catch BackendError.server(let thrown, _) {
                XCTAssertEqual(thrown, status)
            } catch {
                XCTFail("\(status): \(error)")
            }
        }
    }
}
