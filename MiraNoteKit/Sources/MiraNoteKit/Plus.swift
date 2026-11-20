import Foundation
import Observation
import StoreKit

/// MiraNote Plus (api #95 step 4): the subscription group `Plus` with a
/// monthly and a yearly plan, bought through StoreKit 2.
///
/// A purchase needs the writer signed in, because it carries our user id
/// as `appAccountToken`. Every chain the phone holds is sent to the
/// accounts service (`/subscriptions/sync`) after a purchase, on Restore,
/// at launch when signed in and when the App Store reports a change; the
/// server is what the AI services trust. `entitlement` is the phone's own
/// view (`Transaction.currentEntitlements`), shown in Settings.
@MainActor
@Observable
public final class PlusStore {
    /// The design's ids (4.1, build step 9): the bundle id, then the plan.
    /// App Store Connect keeps a product id for good.
    public enum ProductID {
        public static let monthly = "ai.miranote.app.plus.monthly"
        public static let yearly = "ai.miranote.app.plus.yearly"
        public static let all = [yearly, monthly]
    }

    /// The plans, yearly first. Empty until `loadProducts()` succeeds.
    public private(set) var products: [Product] = []
    /// nil: the free plan.
    public private(set) var entitlement: PlusEntitlement?
    public var isPlus: Bool { entitlement != nil }

    @ObservationIgnored private let account: Account
    @ObservationIgnored private let subscriptions: SubscriptionsAPI
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(account: Account, subscriptions: SubscriptionsAPI) {
        self.account = account
        self.subscriptions = subscriptions
    }

    /// At launch: listens for App Store changes (renewals, refunds, Ask to
    /// Buy, purchases made on another device), reads the entitlement, and
    /// when signed in tells the server what the phone holds.
    public func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refreshEntitlement()
            try? await syncWithServer()
        }
    }

    public func loadProducts() async throws {
        let loaded = try await Product.products(for: ProductID.all)
        products = ProductID.all.compactMap { id in loaded.first { $0.id == id } }
    }

    /// Signs in first if needed, then buys `product` for our user id.
    public func purchase(_ product: Product) async throws -> PurchaseOutcome {
        guard await account.permit() else { return .cancelled }
        guard let userID = account.userID.flatMap(UUID.init(uuidString:)) else { throw PlusError.notSignedIn }
        switch try await product.purchase(options: [.appAccountToken(userID)]) {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PlusError.unverified }
            let refused = await Self.settle(sync: syncWithServer, finish: transaction.finish)
            await refreshEntitlement()
            if let refused { throw refused }
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// A purchase the App Store took: the server is told, then the
    /// transaction is finished whatever it said, since Apple has charged.
    /// A chain another account owns is the writer's to hear; any other
    /// failure is not, and the launch sync and Restore send it again.
    static func settle(sync: () async throws -> Void, finish: () async -> Void) async -> PlusError? {
        var refused: PlusError?
        do {
            try await sync()
        } catch PlusError.ownedByAnotherAccount {
            refused = .ownedByAnotherAccount
        } catch {}
        await finish()
        return refused
    }

    /// Restore Purchases (Guideline 3.1.1): signed in first, then the App
    /// Store's own sync, then ours. Whether Plus is on afterwards.
    public func restore() async throws -> Bool {
        guard await account.permit() else { throw PlusError.notSignedIn }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return isPlus
        }
        await refreshEntitlement()
        try await syncWithServer()
        return isPlus
    }

    public func refreshEntitlement() async {
        var facts: [PlusEntitlement.Facts] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result { facts.append(.init(transaction)) }
        }
        entitlement = PlusEntitlement.current(from: facts)
    }

    /// Each chain the phone holds, with Apple's signed transaction and
    /// renewal info (design 5.3). A chain another account owns is
    /// `PlusError.ownedByAnotherAccount`.
    func syncWithServer() async throws {
        guard account.isSignedIn else { return }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductID.all.contains(transaction.productID),
                  let status = await transaction.subscriptionStatus else { continue }
            do {
                try await subscriptions.sync(
                    signedTransaction: status.transaction.jwsRepresentation,
                    signedRenewalInfo: status.renewalInfo.jwsRepresentation
                )
            } catch BackendError.server(let code, _) where code == 403 || code == 409 {
                throw PlusError.ownedByAnotherAccount
            }
        }
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await refreshEntitlement()
        try? await syncWithServer()
        await transaction.finish()
    }
}

public enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    /// Waiting for approval (Ask to Buy); `Transaction.updates` delivers it.
    case pending
    case cancelled
}

public enum PlusError: Error, Equatable, LocalizedError {
    case notSignedIn
    case unverified
    case ownedByAnotherAccount

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(appCopy: "Sign in to use Mira's AI. You can sign in from Settings.")
        case .unverified:
            return String(appCopy: "The App Store could not confirm this purchase.")
        case .ownedByAnotherAccount:
            return String(appCopy: "This purchase belongs to another MiraNote account. Contact us to move it.")
        }
    }
}

/// Plus as the phone sees it.
public struct PlusEntitlement: Equatable, Sendable {
    public let productID: String
    public let expiresAt: Date?

    public var isYearly: Bool { productID == PlusStore.ProductID.yearly }

    /// What decides Plus in one transaction.
    struct Facts: Equatable {
        var productID: String
        var expiresAt: Date?
        var revokedAt: Date?
        var isUpgraded = false
    }

    /// Plus from the current entitlements: a Plus plan neither refunded
    /// nor replaced by an upgrade, the latest expiry first. Not checked
    /// against the clock: StoreKit keeps a subscription in its grace period
    /// among the current entitlements, and that writer keeps Plus.
    static func current(from facts: [Facts]) -> PlusEntitlement? {
        facts
            .filter { PlusStore.ProductID.all.contains($0.productID) && $0.revokedAt == nil && !$0.isUpgraded }
            .max { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
            .map { PlusEntitlement(productID: $0.productID, expiresAt: $0.expiresAt) }
    }
}

extension PlusEntitlement.Facts {
    init(_ transaction: Transaction) {
        self.init(productID: transaction.productID, expiresAt: transaction.expirationDate,
                  revokedAt: transaction.revocationDate, isUpgraded: transaction.isUpgraded)
    }
}

// MARK: - The accounts service

public protocol SubscriptionsAPI: Sendable {
    func sync(signedTransaction: String, signedRenewalInfo: String) async throws
}

/// `POST /subscriptions/sync` on the accounts service, with our access
/// token (miranote-api #113).
public struct LiveSubscriptionsAPI: SubscriptionsAPI {
    private let baseURL: URL
    private let client: HTTPClient

    public init(
        baseURL: URL = MiraNoteConfig.Backend.accountsBaseURL ?? MiraNoteConfig.Backend.Beta.accounts,
        client: HTTPClient = HTTPClient(betaToken: nil)
    ) {
        self.baseURL = baseURL
        self.client = client
    }

    private struct Body: Encodable {
        let signedTransaction: String
        let signedRenewalInfo: String

        enum CodingKeys: String, CodingKey {
            case signedTransaction = "signed_transaction", signedRenewalInfo = "signed_renewal_info"
        }
    }

    public func sync(signedTransaction: String, signedRenewalInfo: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("subscriptions/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Body(signedTransaction: signedTransaction, signedRenewalInfo: signedRenewalInfo)
        )
        _ = try await client.send(request)
    }
}
