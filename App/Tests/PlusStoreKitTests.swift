import MiraNoteKit
import StoreKit
import StoreKitTest
import XCTest
@testable import MiraNote

/// api #95 step 4 against the local StoreKit configuration
/// (App/StoreKit/MiraNote.storekit): the plans and their introductory
/// offers, a purchase for our user id, Restore, and a refund or an expiry
/// taking Plus away.
@MainActor
final class PlusStoreKitTests: XCTestCase {
    private let userID = UUID(uuidString: "00000000-0000-4000-8000-0000000000ab")!
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "MiraNote")
        // From xcodebuild, storekitd on iOS 26.3 and later refuses the
        // configuration ("not installed for development") and StoreKit falls
        // back to the sandbox, where a purchase waits forever. iOS 26.2
        // accepts it, as does a run from Xcode after one Cmd+R.
        try XCTSkipIf(session.storefront != "USA", "storekitd refused the StoreKit configuration")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
    }

    private func store(signedIn: Bool = true) -> (PlusStore, RecordingSubscriptions) {
        let tokens = AccountTokens(accessToken: "a", refreshToken: "r", userID: userID.uuidString,
                                   accessExpiresAt: .distantFuture)
        let account = Account(store: InMemoryTokenStore(signedIn ? tokens : nil), api: NoAccountsAPI(),
                              apple: NoApple())
        let subscriptions = RecordingSubscriptions()
        return (PlusStore(account: account, subscriptions: subscriptions), subscriptions)
    }

    private func product(_ id: String, in store: PlusStore) async throws -> Product {
        if store.products.isEmpty { try await store.loadProducts() }
        return try XCTUnwrap(store.products.first { $0.id == id })
    }

    private func latest(_ id: String) async throws -> Transaction {
        let result = await Transaction.latest(for: id)
        guard case .verified(let transaction) = try XCTUnwrap(result) else { throw PlusError.unverified }
        return transaction
    }

    /// StoreKit reports a refund or an expiry a moment later.
    private func waitForFree(_ store: PlusStore) async throws {
        for _ in 0..<50 where store.isPlus {
            try await Task.sleep(for: .milliseconds(100))
            await store.refreshEntitlement()
        }
        XCTAssertFalse(store.isPlus)
    }

    func testThePlansLoadByIDWithTheirIntroductoryOffers() async throws {
        let (store, _) = store()
        try await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), [PlusStore.ProductID.yearly, PlusStore.ProductID.monthly])

        let monthly = try await product(PlusStore.ProductID.monthly, in: store)
        XCTAssertEqual(monthly.price, Decimal(string: "5.99"))
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        let monthlyIntro = try XCTUnwrap(monthly.subscription?.introductoryOffer)
        XCTAssertEqual(monthlyIntro.paymentMode, .payAsYouGo)
        XCTAssertEqual(monthlyIntro.price, Decimal(string: "2.99"))
        XCTAssertEqual(monthlyIntro.periodCount, 2)

        let yearly = try await product(PlusStore.ProductID.yearly, in: store)
        XCTAssertEqual(yearly.price, Decimal(string: "39.99"))
        XCTAssertEqual(yearly.subscription?.introductoryOffer?.paymentMode, .payUpFront)
        XCTAssertEqual(yearly.subscription?.subscriptionGroupID, monthly.subscription?.subscriptionGroupID)
        let eligible = await monthly.subscription?.isEligibleForIntroOffer
        XCTAssertEqual(eligible, true)
    }

    func testThePaywallStatesThePriceAfterTheOffer() async throws {
        let (store, _) = store()
        let monthly = try await product(PlusStore.ProductID.monthly, in: store)
        let period = try XCTUnwrap(monthly.subscription?.subscriptionPeriod)
        let intro = try XCTUnwrap(monthly.subscription?.introductoryOffer)
        XCTAssertEqual(PaywallSheet.price(monthly.displayPrice, per: period), "\(monthly.displayPrice) a month")
        XCTAssertEqual(PaywallSheet.length(intro.period, times: intro.periodCount), "2 months")
    }

    func testAPurchaseGivesPlusForOurUserIDAndTellsTheServer() async throws {
        let (store, subscriptions) = store()
        let outcome = try await store.purchase(try await product(PlusStore.ProductID.monthly, in: store))

        XCTAssertEqual(outcome, .purchased)
        XCTAssertEqual(store.entitlement?.productID, PlusStore.ProductID.monthly)
        let transaction = try await latest(PlusStore.ProductID.monthly)
        XCTAssertEqual(transaction.appAccountToken, userID)
        XCTAssertEqual(subscriptions.synced.count, 1)
        XCTAssertFalse(subscriptions.synced[0].transaction.isEmpty)
        XCTAssertFalse(subscriptions.synced[0].renewalInfo.isEmpty)
    }

    func testTheIntroductoryOfferIsTakenOnce() async throws {
        let (store, _) = store()
        let monthly = try await product(PlusStore.ProductID.monthly, in: store)
        _ = try await store.purchase(monthly)

        let transaction = try await latest(PlusStore.ProductID.monthly)
        if #available(iOS 17.2, *) {
            XCTAssertEqual(transaction.offer?.type, .introductory)
        } else {
            XCTAssertEqual(transaction.offerType, .introductory)
        }
        let eligible = await monthly.subscription?.isEligibleForIntroOffer
        XCTAssertEqual(eligible, false, "one introductory offer per group")
    }

    func testRestoreBringsPlusBackAndTellsTheServer() async throws {
        _ = try await session.buyProduct(identifier: PlusStore.ProductID.yearly)
        let (store, subscriptions) = store()

        let restored = try await store.restore()

        XCTAssertTrue(restored)
        XCTAssertEqual(store.entitlement?.productID, PlusStore.ProductID.yearly)
        XCTAssertEqual(subscriptions.synced.count, 1)
    }

    func testRestoreWithNothingBoughtIsTheFreePlan() async throws {
        let (store, subscriptions) = store()
        let restored = try await store.restore()
        XCTAssertFalse(restored)
        XCTAssertEqual(subscriptions.synced.count, 0)
    }

    func testAPurchaseOwnedByAnotherAccountSaysSo() async throws {
        _ = try await session.buyProduct(identifier: PlusStore.ProductID.monthly)
        let (store, subscriptions) = store()
        subscriptions.error = BackendError.server(status: 403, detail: nil)
        do {
            _ = try await store.restore()
            XCTFail("expected another account's purchase")
        } catch {
            XCTAssertEqual(error as? PlusError, .ownedByAnotherAccount)
        }
    }

    func testARefundTakesPlusAway() async throws {
        let (store, _) = store()
        _ = try await store.purchase(try await product(PlusStore.ProductID.monthly, in: store))
        XCTAssertTrue(store.isPlus)

        try session.refundTransaction(identifier: UInt(try await latest(PlusStore.ProductID.monthly).id))

        try await waitForFree(store)
    }

    func testAnExpiredSubscriptionIsTheFreePlan() async throws {
        let (store, _) = store()
        _ = try await store.purchase(try await product(PlusStore.ProductID.yearly, in: store))
        XCTAssertTrue(store.isPlus)

        try session.expireSubscription(productIdentifier: PlusStore.ProductID.yearly)

        try await waitForFree(store)
    }

    func testSignedOutAndNotNowBuysNothing() async throws {
        let (store, subscriptions) = store(signedIn: false)
        let outcome = try await store.purchase(try await product(PlusStore.ProductID.monthly, in: store))
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(store.isPlus)
        XCTAssertEqual(subscriptions.synced.count, 0)
    }
}

/// The local StoreKit configuration sells the ids the app asks for, so Run
/// and the StoreKit tests cannot drift from `PlusStore.ProductID`. Reads
/// the file itself: no StoreKit session, so it runs on every simulator.
final class StoreKitConfigurationTests: XCTestCase {
    func testTheConfigurationSellsThePlusPlans() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MiraNote", withExtension: "storekit"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let groups = try XCTUnwrap(object["subscriptionGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.compactMap { $0["name"] as? String }, ["Plus"])
        let plans = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(Set(plans.compactMap { $0["productID"] as? String }), Set(PlusStore.ProductID.all))
    }

    /// Yearly is the higher level (1 is the top), so monthly to yearly is
    /// an upgrade and the reverse a downgrade, not a crossgrade. App Store
    /// Connect holds the same levels.
    func testYearlyRanksAboveMonthly() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MiraNote", withExtension: "storekit"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let groups = try XCTUnwrap(object["subscriptionGroups"] as? [[String: Any]])
        let plans = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let levels = Dictionary(uniqueKeysWithValues: plans.compactMap { plan in
            (plan["productID"] as? String).map { ($0, plan["groupNumber"] as? Int) }
        })
        XCTAssertEqual(levels[PlusStore.ProductID.yearly], 1)
        XCTAssertEqual(levels[PlusStore.ProductID.monthly], 2)
    }
}

// MARK: - Doubles

private final class RecordingSubscriptions: SubscriptionsAPI, @unchecked Sendable {
    var synced: [(transaction: String, renewalInfo: String)] = []
    var error: Error?

    func sync(signedTransaction: String, signedRenewalInfo: String) async throws {
        if let error { throw error }
        synced.append((signedTransaction, signedRenewalInfo))
    }
}

private struct NoAccountsAPI: AccountsAPI {
    func signIn(identityToken: String, nonce: String) async throws -> AccountTokens { throw AccountError.signedOut }
    func refresh(refreshToken: String) async throws -> AccountTokens { throw AccountError.signedOut }
    func signOut(refreshToken: String) async throws {}
    func deleteAccount(accessToken: String, authorizationCode: String) async throws -> Bool {
        throw AccountError.signedOut
    }
}

private struct NoApple: AppleCredentialProvider {
    func identityToken(nonceHash: String) async throws -> String { throw AppleSignInError.cancelled }
    func authorizationCode() async throws -> String { throw AppleSignInError.cancelled }
}
