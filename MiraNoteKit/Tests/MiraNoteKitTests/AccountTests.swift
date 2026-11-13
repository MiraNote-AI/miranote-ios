import XCTest
@testable import MiraNoteKit

/// api #95 step 2: Sign in with Apple, our tokens kept and refreshed, sign
/// out, and the sign-in asked right after AI consent.
@MainActor
final class AccountTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func tokens(_ number: Int, expiresIn: TimeInterval = 3600) -> AccountTokens {
        AccountTokens(accessToken: "access-\(number)", refreshToken: "refresh-\(number)", userID: "user-1",
                      accessExpiresAt: clock.addingTimeInterval(expiresIn))
    }

    private func account(store: InMemoryTokenStore, api: FakeAccountsAPI,
                         apple: FakeApple = FakeApple()) -> Account {
        Account(store: store, api: api, apple: apple, now: { [unowned self] in clock })
    }

    // MARK: Sign-in

    func testSignInSendsAppleTheNonceHashAndTheServerTheRawNonce() async throws {
        let store = InMemoryTokenStore()
        let api = FakeAccountsAPI(signInResult: tokens(1))
        let apple = FakeApple()
        let account = account(store: store, api: api, apple: apple)
        XCTAssertFalse(account.isSignedIn)

        try await account.signIn()

        XCTAssertTrue(account.isSignedIn)
        XCTAssertEqual(store.load(), tokens(1))
        let sent = try XCTUnwrap(api.signIns.first)
        XCTAssertEqual(sent.identityToken, "apple-identity-token")
        XCTAssertEqual(apple.nonceHashes, [Account.nonceHash(sent.nonce)])
        XCTAssertNotEqual(sent.nonce, apple.nonceHashes.first)
        XCTAssertGreaterThanOrEqual(sent.nonce.count, 43, "32 random bytes")
    }

    func testNonceHashIsSHA256Hex() {
        XCTAssertEqual(Account.nonceHash("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNotEqual(Account.newNonce(), Account.newNonce())
    }

    func testCancelledAppleSheetKeepsTheWriterSignedOut() async {
        let store = InMemoryTokenStore()
        let account = account(store: store, api: FakeAccountsAPI(signInResult: tokens(1)),
                              apple: FakeApple(error: AppleSignInError.cancelled))
        do {
            try await account.signIn()
            XCTFail("expected cancelled")
        } catch {
            XCTAssertEqual(error as? AppleSignInError, .cancelled)
        }
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(store.load())
    }

    func testTokensInTheStoreMeanSignedInAtLaunch() {
        let account = account(store: InMemoryTokenStore(tokens(1)), api: FakeAccountsAPI())
        XCTAssertTrue(account.isSignedIn)
    }

    // MARK: The sheet

    func testPermitShowsTheSheetOnceForParallelRequests() async {
        let account = account(store: InMemoryTokenStore(), api: FakeAccountsAPI(signInResult: tokens(1)))
        var sheets = 0
        account.present = { [unowned account] in
            sheets += 1
            Task { @MainActor in
                try? await account.signIn()
                account.answer(true)
            }
        }
        async let first = account.permit()
        async let second = account.permit()
        let answers = await [first, second]
        XCTAssertEqual(answers, [true, true])
        XCTAssertEqual(sheets, 1)
        let again = await account.permit()
        XCTAssertTrue(again)
        XCTAssertEqual(sheets, 1, "signed in: never asked again")
    }

    func testNotNowAnswersNoAndIsNotKept() async {
        let account = account(store: InMemoryTokenStore(), api: FakeAccountsAPI())
        var sheets = 0
        account.present = { [unowned account] in
            sheets += 1
            Task { @MainActor in account.answer(false) }
        }
        let first = await account.permit()
        let second = await account.permit()
        XCTAssertEqual([first, second], [false, false])
        XCTAssertEqual(sheets, 2, "the next action asks again")
        XCTAssertFalse(account.isSignedIn)
    }

    func testNoPresenterSaysNo() async {
        let account = account(store: InMemoryTokenStore(), api: FakeAccountsAPI())
        let allowed = await account.permit()
        XCTAssertFalse(allowed)
    }

    // MARK: Access tokens and refresh

    func testAFreshAccessTokenIsUsedAsIs() async throws {
        let api = FakeAccountsAPI()
        let account = account(store: InMemoryTokenStore(tokens(1)), api: api)
        let token = try await account.accessToken()
        XCTAssertEqual(token, "access-1")
        XCTAssertEqual(api.refreshes, [])
    }

    func testAnExpiringAccessTokenIsRefreshedAndTheNewPairKept() async throws {
        let store = InMemoryTokenStore(tokens(1, expiresIn: 30))
        let api = FakeAccountsAPI(refreshResults: [.success(tokens(2))])
        let account = account(store: store, api: api)
        let token = try await account.accessToken()
        XCTAssertEqual(token, "access-2")
        XCTAssertEqual(api.refreshes, ["refresh-1"])
        XCTAssertEqual(store.load(), tokens(2), "the rotated refresh token replaces the old one")
    }

    func testParallelCallersShareOneRefresh() async throws {
        let store = InMemoryTokenStore(tokens(1, expiresIn: -10))
        let api = FakeAccountsAPI(refreshResults: [.success(tokens(2))])
        api.refreshDelay = 50_000_000
        let account = account(store: store, api: api)
        async let first = account.accessToken()
        async let second = account.accessToken()
        let results = try await [first, second]
        XCTAssertEqual(results, ["access-2", "access-2"])
        XCTAssertEqual(api.refreshes, ["refresh-1"], "a rotated token is never presented twice")
    }

    func testARefusedRefreshSignsOut() async {
        let store = InMemoryTokenStore(tokens(1, expiresIn: -10))
        let api = FakeAccountsAPI(refreshResults: [.failure(BackendError.server(status: 401, detail: nil))])
        let account = account(store: store, api: api)
        do {
            _ = try await account.accessToken()
            XCTFail("expected signed out")
        } catch {
            XCTAssertEqual(error as? AccountError, .signedOut)
        }
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(store.load())
    }

    func testANetworkFailureKeepsTheTokens() async {
        let store = InMemoryTokenStore(tokens(1, expiresIn: -10))
        let api = FakeAccountsAPI(refreshResults: [.failure(BackendError.unreachable)])
        let account = account(store: store, api: api)
        do {
            _ = try await account.accessToken()
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? BackendError, .unreachable)
        }
        XCTAssertTrue(account.isSignedIn)
        XCTAssertEqual(store.load(), tokens(1, expiresIn: -10))
    }

    func testSignedOutHasNoAccessToken() async {
        let account = account(store: InMemoryTokenStore(), api: FakeAccountsAPI())
        do {
            _ = try await account.accessToken()
            XCTFail("expected signed out")
        } catch {
            XCTAssertEqual(error as? AccountError, .signedOut)
        }
    }

    // MARK: Sign out

    func testSignOutForgetsTheTokensAndRevokesTheSignIn() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        let account = account(store: store, api: api)
        await account.signOut()
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(store.load())
        XCTAssertEqual(api.signOuts, ["refresh-1"])
    }

    func testSignOutWorksOffline() async {
        let store = InMemoryTokenStore(tokens(1))
        let api = FakeAccountsAPI()
        api.signOutError = BackendError.unreachable
        let account = account(store: store, api: api)
        await account.signOut()
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(store.load())
    }

    // MARK: After AI consent

    func testAnActionAsksConsentThenSignIn() async throws {
        let defaults = UserDefaults(suiteName: "account-test-\(UUID().uuidString)")!
        let consent = AIConsent(defaults: defaults)
        let account = account(store: InMemoryTokenStore(), api: FakeAccountsAPI(signInResult: tokens(1)))
        var order: [String] = []
        consent.present = { [unowned consent] in
            order.append("consent")
            Task { @MainActor in consent.answer(true) }
        }
        account.present = { [unowned account] in
            order.append("sign-in")
            Task { @MainActor in
                try? await account.signIn()
                account.answer(true)
            }
        }
        consent.signIn = { await account.permit() }
        let services = ServiceContainer.mock.asking(consent)

        _ = try await services.textTransform.transform("tea", mode: .expand)
        XCTAssertEqual(order, ["consent", "sign-in"])
        XCTAssertEqual(consent.sentRequests, 1)

        _ = try await services.textTransform.transform("tea", mode: .clean)
        XCTAssertEqual(order, ["consent", "sign-in"], "neither asks again")
        XCTAssertEqual(consent.sentRequests, 2)
    }

    func testNotNowOnSignInCancelsOnlyThatAction() async {
        let defaults = UserDefaults(suiteName: "account-test-\(UUID().uuidString)")!
        let consent = AIConsent(defaults: defaults, grantedByDefault: true)
        var signInSheets = 0
        consent.signIn = {
            signInSheets += 1
            return false
        }
        let services = ServiceContainer.mock.asking(consent)
        do {
            _ = try await services.chat.reply(to: "hi", sessionID: nil, notes: [], page: nil)
            XCTFail("expected signed out")
        } catch {
            XCTAssertEqual(error as? AIConsentError, .signedOut)
        }
        XCTAssertEqual(consent.sentRequests, 0, "nothing was sent")
        XCTAssertTrue(consent.isGranted, "consent is untouched")
        XCTAssertEqual(signInSheets, 1)
        XCTAssertEqual(AIConsentError.signedOut.errorDescription,
                       "Sign in to use Mira's AI. You can sign in from Settings.")
    }

    func testMoodNeverAsksToSignIn() async throws {
        let defaults = UserDefaults(suiteName: "account-test-\(UUID().uuidString)")!
        let consent = AIConsent(defaults: defaults, grantedByDefault: true)
        consent.signIn = {
            XCTFail("background work never shows the sign-in sheet")
            return false
        }
        let services = ServiceContainer.mock.asking(consent)
        _ = try await services.mood.mood(for: "a calm day")
    }

    // MARK: The live API

    func testLiveAPIPostsAndDecodesThePair() async throws {
        var seen: [SeenRequest] = []
        StubURLProtocol.handler = { request in
            let body = (try? JSONSerialization.jsonObject(with: request.capturedBody ?? Data())) as? [String: Any]
            seen.append(SeenRequest(path: request.url?.path ?? "", body: body ?? [:],
                                    auth: request.value(forHTTPHeaderField: "Authorization")))
            let status = request.url?.path == "/auth/signout" ? 204 : 200
            let json = #"{"access_token":"a","refresh_token":"r","token_type":"Bearer","#
                + #""expires_in":3600,"user_id":"u"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (response, status == 204 ? Data() : Data(json.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let now = clock
        let api = LiveAccountsAPI(baseURL: URL(string: "https://accounts.test")!,
                                  client: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: nil),
                                  now: { now })

        let signedIn = try await api.signIn(identityToken: "id-token", nonce: "raw")
        XCTAssertEqual(signedIn, AccountTokens(accessToken: "a", refreshToken: "r", userID: "u",
                                               accessExpiresAt: now.addingTimeInterval(3600)))
        _ = try await api.refresh(refreshToken: "r0")
        try await api.signOut(refreshToken: "r1")

        XCTAssertEqual(seen.map(\.path), ["/auth/apple", "/auth/refresh", "/auth/signout"])
        XCTAssertEqual(seen[0].body["identity_token"] as? String, "id-token")
        XCTAssertEqual(seen[0].body["nonce"] as? String, "raw")
        XCTAssertEqual(seen[1].body["refresh_token"] as? String, "r0")
        XCTAssertEqual(seen[2].body["refresh_token"] as? String, "r1")
        XCTAssertEqual(seen.compactMap(\.auth), [], "no beta token to the accounts service")
    }
}

/// Review of #200: a refused refresh reaches every caller waiting on it
/// as `signedOut`, and a Keychain that keeps nothing is not a sign-in.
extension AccountTests {
    func testParallelCallersAreBothSignedOutByARefusedRefresh() async {
        let store = InMemoryTokenStore(tokens(1, expiresIn: -10))
        let api = FakeAccountsAPI(refreshResults: [.failure(BackendError.server(status: 401, detail: nil))])
        api.refreshDelay = 50_000_000
        let account = account(store: store, api: api)
        func attempt() async -> Result<String, Error> {
            do { return .success(try await account.accessToken()) } catch { return .failure(error) }
        }
        async let first = attempt()
        async let second = attempt()
        let results = await [first, second]
        for result in results {
            XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? AccountError, .signedOut) }
        }
        XCTAssertEqual(api.refreshes, ["refresh-1"])
        XCTAssertFalse(account.isSignedIn)
    }

    func testAKeychainThatKeepsNothingIsNotASignIn() async {
        let account = Account(store: DroppingTokenStore(), api: FakeAccountsAPI(signInResult: tokens(1)),
                              apple: FakeApple(), now: { [unowned self] in clock })
        do {
            try await account.signIn()
            XCTFail("expected not saved")
        } catch {
            XCTAssertEqual(error as? AccountError, .notSaved)
        }
        XCTAssertFalse(account.isSignedIn, "no tokens to send: not signed in")
    }
}

// MARK: - Doubles

private struct SeenRequest {
    let path: String
    let body: [String: Any]
    let auth: String?
}

private final class FakeApple: AppleCredentialProvider, @unchecked Sendable {
    private let error: Error?
    var nonceHashes: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func identityToken(nonceHash: String) async throws -> String {
        nonceHashes.append(nonceHash)
        if let error { throw error }
        return "apple-identity-token"
    }
}

/// A Keychain that refuses every write.
private struct DroppingTokenStore: TokenStore {
    func load() -> AccountTokens? { nil }
    func save(_ tokens: AccountTokens?) {}
}

private final class FakeAccountsAPI: AccountsAPI, @unchecked Sendable {
    var signInResult: AccountTokens?
    var refreshResults: [Result<AccountTokens, Error>]
    var refreshDelay: UInt64 = 0
    var signOutError: Error?
    var signIns: [(identityToken: String, nonce: String)] = []
    var refreshes: [String] = []
    var signOuts: [String] = []

    init(signInResult: AccountTokens? = nil, refreshResults: [Result<AccountTokens, Error>] = []) {
        self.signInResult = signInResult
        self.refreshResults = refreshResults
    }

    func signIn(identityToken: String, nonce: String) async throws -> AccountTokens {
        signIns.append((identityToken, nonce))
        guard let signInResult else { throw BackendError.server(status: 401, detail: nil) }
        return signInResult
    }

    func refresh(refreshToken: String) async throws -> AccountTokens {
        refreshes.append(refreshToken)
        if refreshDelay > 0 { try await Task.sleep(nanoseconds: refreshDelay) }
        return try refreshResults.removeFirst().get()
    }

    func signOut(refreshToken: String) async throws {
        signOuts.append(refreshToken)
        if let signOutError { throw signOutError }
    }
}
