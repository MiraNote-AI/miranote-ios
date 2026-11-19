import XCTest
@testable import MiraNoteKit

/// api #95 step 3: a signed-in writer's AI requests carry our access token,
/// a 401 renews it once for every request that got it, signed out the beta
/// token goes as before, and a used-up allowance is `limitReached`.
@MainActor
final class UserTokenTests: XCTestCase {
    private let url = URL(string: "http://localhost:8001/expand")!
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func tokens(_ number: Int) -> AccountTokens {
        AccountTokens(accessToken: "access-\(number)", refreshToken: "refresh-\(number)", userID: "user-1",
                      accessExpiresAt: clock.addingTimeInterval(3600))
    }

    private func account(_ tokens: AccountTokens?, api: FakeAccountsAPI = FakeAccountsAPI()) -> Account {
        let now = clock
        return Account(store: InMemoryTokenStore(tokens), api: api, apple: FakeApple(), now: { now })
    }

    private func client(_ source: UserTokenSource?) -> HTTPClient {
        HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "beta", userTokens: source)
    }

    private func request() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        return request
    }

    nonisolated private static func answer(_ request: URLRequest, _ status: Int,
                                           _ body: String = "{}") -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    /// Answers 401 to `access-1`, 200 to anything else; records each try.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [(auth: String?, id: String?)] = []

        var all: [(auth: String?, id: String?)] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }

        func handle(_ request: URLRequest) -> (HTTPURLResponse, Data) {
            let auth = request.value(forHTTPHeaderField: "Authorization")
            lock.lock()
            seen.append((auth, request.value(forHTTPHeaderField: "X-Request-ID")))
            lock.unlock()
            return UserTokenTests.answer(request, auth == "Bearer access-1" ? 401 : 200)
        }
    }

    func testSignedOutSendsTheBetaTokenAndNoRequestID() async throws {
        let recorder = Recorder()
        StubURLProtocol.handler = recorder.handle
        _ = try await client(account(nil)).send(request())
        _ = try await client(nil).send(request())
        XCTAssertEqual(recorder.all.map(\.auth), ["Bearer beta", "Bearer beta"])
        XCTAssertEqual(recorder.all.compactMap(\.id), [])
    }

    func testSignedInSendsOurAccessTokenWithARequestID() async throws {
        let recorder = Recorder()
        StubURLProtocol.handler = recorder.handle
        _ = try await client(account(tokens(2))).send(request())
        XCTAssertEqual(recorder.all.map(\.auth), ["Bearer access-2"])
        XCTAssertNotNil(UUID(uuidString: recorder.all.first?.id ?? ""))
    }

    func testA401RenewsTheTokenAndRetriesWithTheSameRequestID() async throws {
        let recorder = Recorder()
        StubURLProtocol.handler = recorder.handle
        let api = FakeAccountsAPI(refreshResults: [.success(tokens(2))])
        _ = try await client(account(tokens(1), api: api)).send(request())
        XCTAssertEqual(recorder.all.map(\.auth), ["Bearer access-1", "Bearer access-2"])
        XCTAssertEqual(Set(recorder.all.compactMap(\.id)).count, 1, "one action, one id")
        XCTAssertEqual(api.refreshes, ["refresh-1"])
    }

    func testParallelRequestsRefusedTogetherShareOneRefresh() async throws {
        let recorder = Recorder()
        StubURLProtocol.handler = recorder.handle
        let api = FakeAccountsAPI(refreshResults: [.success(tokens(2))])
        api.refreshDelay = 50_000_000
        let http = client(account(tokens(1), api: api))
        async let first = http.send(request())
        async let second = http.send(request())
        async let third = http.send(request())
        _ = try await [first, second, third]
        XCTAssertEqual(api.refreshes, ["refresh-1"], "a rotated refresh token is never presented twice")
        XCTAssertEqual(recorder.all.filter { $0.auth == "Bearer access-2" }.count, 3, "all three retried")
    }

    func testARefusedRefreshSignsOutAndSaysSo() async {
        StubURLProtocol.handler = Recorder().handle
        let api = FakeAccountsAPI(refreshResults: [.failure(BackendError.server(status: 401, detail: nil))])
        let account = account(tokens(1), api: api)
        do {
            _ = try await client(account).send(request())
            XCTFail("expected signed out")
        } catch {
            XCTAssertEqual(error as? AccountError, .signedOut)
            XCTAssertEqual(error.localizedDescription, "Your sign-in has ended. Sign in again to use Mira's AI.")
        }
        XCTAssertFalse(account.isSignedIn)
    }

    /// A build that offers no sign-in installs no token source
    /// (`SignInPresenter.install`), and every client built with the default
    /// sends what it sent before this change: the beta token, no request id,
    /// the body untouched.
    func testABuildWithoutSignInSendsTheBetaTokenAsBefore() async throws {
        XCTAssertNil(UserTokens.installed)
        var seen: [URLRequest] = []
        StubURLProtocol.handler = { request in
            seen.append(request)
            return Self.answer(request, 200)
        }
        let body = Data(#"{"text": "tea"}"#.utf8)
        var sent = request()
        sent.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sent.httpBody = body
        _ = try await HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "beta").send(sent)

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.value(forHTTPHeaderField: "Authorization"), "Bearer beta")
        XCTAssertNil(seen.first?.value(forHTTPHeaderField: "X-Request-ID"))
        XCTAssertEqual(seen.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(seen.first?.capturedBody, body)
    }

    func testTheAccountsServiceNeverGetsOurAccessToken() async throws {
        UserTokens.installed = account(tokens(2))
        defer { UserTokens.installed = nil }
        var auth: [String?] = []
        StubURLProtocol.handler = { request in
            auth.append(request.value(forHTTPHeaderField: "Authorization"))
            return Self.answer(request, 200, #"{"access_token":"a","refresh_token":"r","expires_in":1,"user_id":"u"}"#)
        }
        _ = try await LiveAccountsAPI(baseURL: URL(string: "https://accounts.test")!,
                                      client: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: nil,
                                                         userTokens: nil))
            .refresh(refreshToken: "r0")
        // The default client reads the installed source.
        _ = try await HTTPClient(session: StubURLProtocol.makeSession(), betaToken: "beta").send(request())
        XCTAssertEqual(auth, [nil, "Bearer access-2"])
    }

    /// Signing out cancels a refresh that is out. Every request waiting on
    /// it ends as signed out, not as the cancellation, which the live
    /// accounts client reads as `.unreachable` ("Couldn't reach MiraNote's
    /// AI server ... the team needs to know").
    func testSigningOutDuringARefreshEndsItsRequestsAsSignedOut() async throws {
        StubURLProtocol.handler = {
            Self.answer($0, $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" ? 401 : 200)
        }
        for cancelled in [nil, BackendError.unreachable] as [BackendError?] {
            let api = FakeAccountsAPI(refreshResults: [.success(tokens(2))])
            api.refreshDelay = 5_000_000_000
            api.cancelledRefreshError = cancelled
            let account = account(tokens(1), api: api)
            let requests = (0..<2).map { _ in Task { try await client(account).send(request()) } }
            for _ in 0..<500 where api.refreshes.isEmpty { try await Task.sleep(nanoseconds: 2_000_000) }
            XCTAssertEqual(api.refreshes, ["refresh-1"])
            await account.signOut()
            for request in requests {
                do {
                    _ = try await request.value
                    XCTFail("sent after sign-out")
                } catch {
                    XCTAssertEqual(error as? AccountError, .signedOut, "\(error), cancelled as \(cancelled as Any)")
                }
            }
            XCTAssertNil(account.userID, "the renewed pair was not kept")
        }
    }

    // MARK: Limits

    private func failure(status: Int, body: String) async -> Error? {
        StubURLProtocol.handler = { Self.answer($0, status, body) }
        do {
            _ = try await client(account(tokens(2))).send(request())
            return nil
        } catch {
            return error
        }
    }

    func testAQuota429IsLimitReached() async {
        let body = #"{"reason": "quota", "feature": "image_generate", "plan": "free", "limit": 5,"#
            + #" "resets_at": "2026-12-01T00:00:00+00:00"}"#
        let error = await failure(status: 429, body: body)
        XCTAssertEqual(error as? BackendError, .limitReached(AILimit(feature: "image_generate", plan: "free")))
        XCTAssertEqual(error?.localizedDescription,
                       "You've reached the free limit for this. MiraNote Plus gives you more.")
    }

    func testAPlusWritersLimitSaysTryLater() async {
        let error = await failure(status: 429, body: #"{"reason": "quota", "feature": "chat", "plan": "plus"}"#)
        XCTAssertEqual(error as? BackendError, .limitReached(AILimit(feature: "chat", plan: "plus")))
        XCTAssertEqual(error?.localizedDescription, "You've reached this limit for now. Try again later.")
    }

    func testTheBetaRateLimitStaysA429() async {
        let error = await failure(status: 429, body: #"{"detail": "beta rate limit exceeded"}"#)
        guard case .server(429, _) = error as? BackendError else { return XCTFail("got \(String(describing: error))") }
    }

    // MARK: The paywall at a used-up allowance

    private final class LimitedText: TextTransformService {
        let limit: AILimit
        init(_ limit: AILimit) { self.limit = limit }
        func transform(_ text: String, mode: TextTransformMode) async throws -> String {
            throw BackendError.limitReached(limit)
        }
    }

    private func consent() -> AIConsent {
        AIConsent(defaults: UserDefaults(suiteName: "limit-test-\(UUID().uuidString)")!, grantedByDefault: true)
    }

    func testAFreeLimitOnAnActionShowsThePaywall() async {
        let consent = consent()
        var shown: [AILimit] = []
        consent.limitReached = { shown.append($0) }
        let free = AILimit(feature: "expand", plan: "free")
        let services = ServiceContainer(
            textTransform: LimitedText(free), voiceTranscription: MockVoiceTranscriptionService(),
            stickerGeneration: MockStickerGenerationService(), styleTransfer: MockStyleTransferService()
        ).asking(consent)
        do {
            _ = try await services.textTransform.transform("tea", mode: .expand)
            XCTFail("expected the limit")
        } catch {
            XCTAssertEqual(error as? BackendError, .limitReached(free), "the action still fails")
        }
        XCTAssertEqual(shown, [free])
    }

    func testAPlusLimitDoesNotOfferPlus() async {
        let consent = consent()
        var shown = 0
        consent.limitReached = { _ in shown += 1 }
        let services = ServiceContainer(
            textTransform: LimitedText(AILimit(feature: "expand", plan: "plus")),
            voiceTranscription: MockVoiceTranscriptionService(),
            stickerGeneration: MockStickerGenerationService(), styleTransfer: MockStyleTransferService()
        ).asking(consent)
        _ = try? await services.textTransform.transform("tea", mode: .expand)
        XCTAssertEqual(shown, 0)
    }
}

/// What the phone counts as Plus (api #95 step 4).
final class PlusEntitlementTests: XCTestCase {
    private typealias Facts = PlusEntitlement.Facts
    private let monthly = PlusStore.ProductID.monthly
    private let yearly = PlusStore.ProductID.yearly
    private let soon = Date(timeIntervalSince1970: 1_800_000_000)

    /// The ids App Store Connect will hold for good: the design's, which
    /// follow the bundle id (accounts-and-subscriptions design 4.1 and
    /// build step 9, decided 2026-11-13). The server's rows and tests use
    /// them too (miranote-api #113).
    func testThePlansAreTheDesignsProductIDs() {
        XCTAssertEqual(PlusStore.ProductID.monthly, "ai.miranote.app.plus.monthly")
        XCTAssertEqual(PlusStore.ProductID.yearly, "ai.miranote.app.plus.yearly")
        XCTAssertEqual(PlusStore.ProductID.all, [PlusStore.ProductID.yearly, PlusStore.ProductID.monthly])
    }

    func testNoTransactionsIsTheFreePlan() {
        XCTAssertNil(PlusEntitlement.current(from: []))
    }

    func testAPlusPlanIsPlus() {
        let facts = [Facts(productID: monthly, expiresAt: soon)]
        XCTAssertEqual(PlusEntitlement.current(from: facts),
                       PlusEntitlement(productID: monthly, expiresAt: soon))
    }

    func testARefundedPlanIsNotPlus() {
        let facts = [Facts(productID: yearly, expiresAt: soon, revokedAt: soon.addingTimeInterval(-60))]
        XCTAssertNil(PlusEntitlement.current(from: facts))
    }

    func testAnUpgradedPlanGivesWayToTheNewOne() {
        let facts = [Facts(productID: monthly, expiresAt: soon.addingTimeInterval(86_400), isUpgraded: true),
                     Facts(productID: yearly, expiresAt: soon.addingTimeInterval(365 * 86_400))]
        XCTAssertEqual(PlusEntitlement.current(from: facts)?.productID, yearly)
        XCTAssertEqual(PlusEntitlement.current(from: facts)?.isYearly, true)
    }

    func testAnotherProductIsNotPlus() {
        XCTAssertNil(PlusEntitlement.current(from: [Facts(productID: "tips.small", expiresAt: soon)]))
    }

    func testTheLatestExpiryWins() {
        let facts = [Facts(productID: monthly, expiresAt: soon),
                     Facts(productID: yearly, expiresAt: soon.addingTimeInterval(100))]
        XCTAssertEqual(PlusEntitlement.current(from: facts)?.productID, yearly)
    }
}

/// `POST /subscriptions/sync` (miranote-api #113).
@MainActor
final class LiveSubscriptionsAPITests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testSyncPostsBothSignedStringsWithOurToken() async throws {
        var seen: (path: String, auth: String?, body: [String: Any])?
        StubURLProtocol.handler = { request in
            let body = (try? JSONSerialization.jsonObject(with: request.capturedBody ?? Data())) as? [String: Any]
            seen = (request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization"), body ?? [:])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"plan": "plus"}"#.utf8))
        }
        let account = Account(
            store: InMemoryTokenStore(AccountTokens(accessToken: "access-9", refreshToken: "r", userID: "u",
                                                    accessExpiresAt: .distantFuture)),
            api: FakeAccountsAPI(), apple: FakeApple()
        )
        let api = LiveSubscriptionsAPI(
            baseURL: URL(string: "https://accounts.test")!,
            client: HTTPClient(session: StubURLProtocol.makeSession(), betaToken: nil, userTokens: account)
        )
        try await api.sync(signedTransaction: "tx.jws", signedRenewalInfo: "renewal.jws")
        XCTAssertEqual(seen?.path, "/subscriptions/sync")
        XCTAssertEqual(seen?.auth, "Bearer access-9")
        XCTAssertEqual(seen?.body["signed_transaction"] as? String, "tx.jws")
        XCTAssertEqual(seen?.body["signed_renewal_info"] as? String, "renewal.jws")
    }
}
