import CryptoKit
import Foundation
import Observation
import Security

/// The writer's MiraNote account (api #95 step 2): Sign in with Apple at
/// the first server-AI action, right after AI consent, and our own tokens
/// from the accounts service kept in the Keychain. Signed out, everything
/// that runs on the phone keeps working; only server AI asks to sign in.
///
/// `permit()` shows the sign-in sheet through `present` and waits for
/// `answer(_:)`, like `AIConsent`. The sheet's Apple button runs
/// `signIn()`; Not now answers false and cancels only that action.
@MainActor
@Observable
public final class Account {
    public private(set) var isSignedIn: Bool

    /// The sheet is up, waiting for `answer(_:)`.
    public private(set) var isAsking = false

    /// Shows the sheet. Unset, nobody can sign in, so `permit()` says no.
    @ObservationIgnored public var present: (@MainActor () -> Void)?

    @ObservationIgnored private let store: TokenStore
    @ObservationIgnored private let api: AccountsAPI
    @ObservationIgnored private let apple: AppleCredentialProvider
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var waiting: [CheckedContinuation<Bool, Never>] = []
    /// One refresh at a time: parallel callers share it, so a rotated
    /// refresh token is never presented twice.
    @ObservationIgnored private var refreshing: Task<AccountTokens, Error>?

    /// An access token this close to expiry is refreshed before use.
    static let refreshMargin: TimeInterval = 60

    public init(
        store: TokenStore,
        api: AccountsAPI,
        apple: AppleCredentialProvider,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.api = api
        self.apple = apple
        self.now = now
        isSignedIn = store.load() != nil
    }

    /// True at once when signed in. Otherwise shows the sheet (once for any
    /// number of requests waiting together) and returns its answer.
    public func permit() async -> Bool {
        if isSignedIn { return true }
        guard let present else { return false }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if !isAsking {
                isAsking = true
                present()
            }
        }
    }

    /// The sheet's answer: true once `signIn()` succeeded, false for Not now.
    public func answer(_ signedIn: Bool) {
        isAsking = false
        let answered = waiting
        waiting = []
        for continuation in answered { continuation.resume(returning: signedIn && isSignedIn) }
    }

    /// Asks Apple for an identity token bound to a fresh nonce, trades it
    /// for our tokens and keeps them. Throws `AppleSignInError.cancelled`
    /// when the writer closes Apple's sheet.
    public func signIn() async throws {
        let nonce = Self.newNonce()
        let identityToken = try await apple.identityToken(nonceHash: Self.nonceHash(nonce))
        let tokens = try await api.signIn(identityToken: identityToken, nonce: nonce)
        store.save(tokens)
        // A Keychain that refused the write keeps nothing: say so now, not
        // at the first request that needs a token.
        guard store.load() == tokens else { throw AccountError.notSaved }
        isSignedIn = true
    }

    /// Forgets our tokens at once, then tells the server to revoke the
    /// sign-in. The server call is best effort: signed out on the phone is
    /// what the writer asked for, and the refresh token is gone either way.
    public func signOut() async {
        let tokens = store.load()
        refreshing?.cancel()
        refreshing = nil
        store.save(nil)
        isSignedIn = false
        if let tokens { try? await api.signOut(refreshToken: tokens.refreshToken) }
    }

    /// A valid access token for `Authorization: Bearer`, refreshed first when
    /// it is about to expire. A refused refresh token signs the writer out
    /// (`AccountError.signedOut`); a network failure keeps the tokens.
    public func accessToken() async throws -> String {
        guard let tokens = store.load() else { throw AccountError.signedOut }
        if tokens.accessExpiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return tokens.accessToken
        }
        return try await refreshed(tokens).accessToken
    }

    private func refreshed(_ tokens: AccountTokens) async throws -> AccountTokens {
        if let refreshing {
            // Another caller's refresh: its outcome, read the same way.
            do {
                let fresh = try await refreshing.value
                guard isSignedIn else { throw AccountError.signedOut }
                return fresh
            } catch BackendError.server(status: 401, _) {
                throw AccountError.signedOut
            }
        }
        let task = Task { [api] in try await api.refresh(refreshToken: tokens.refreshToken) }
        refreshing = task
        defer { if refreshing == task { refreshing = nil } }
        do {
            let fresh = try await task.value
            // Signed out while the refresh was out: do not sign back in.
            guard isSignedIn else { throw AccountError.signedOut }
            store.save(fresh)
            return fresh
        } catch BackendError.server(status: 401, _) {
            store.save(nil)
            isSignedIn = false
            throw AccountError.signedOut
        }
    }

    /// 32 random bytes, base64url: the raw nonce the server checks. The
    /// system generator is cryptographically secure and cannot fail, unlike
    /// SecRandomCopyBytes, whose failure would leave 32 zero bytes.
    static func newNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// What Apple's request carries and the identity token echoes: SHA-256
    /// hex of the raw nonce (the server recomputes it).
    static func nonceHash(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum AccountError: Error, Equatable {
    /// No tokens, or the server no longer accepts them: sign in again.
    case signedOut
    /// Signed in with the server, but the Keychain did not keep the tokens.
    case notSaved
}

public enum AppleSignInError: Error, Equatable {
    /// The writer closed Apple's sheet.
    case cancelled
    /// Apple answered without an identity token.
    case noIdentityToken
}

/// Our tokens from the accounts service.
public struct AccountTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var userID: String
    public var accessExpiresAt: Date

    public init(accessToken: String, refreshToken: String, userID: String, accessExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userID = userID
        self.accessExpiresAt = accessExpiresAt
    }
}

/// Asks Apple for an identity token whose `nonce` claim is `nonceHash`:
/// AuthenticationServices in the app, a mock under -UITEST.
public protocol AppleCredentialProvider: Sendable {
    @MainActor func identityToken(nonceHash: String) async throws -> String
}

// MARK: - Token storage

public protocol TokenStore: Sendable {
    func load() -> AccountTokens?
    /// nil deletes.
    func save(_ tokens: AccountTokens?)
}

/// The tokens as one generic-password item, this device only, readable
/// after the first unlock (a refresh can run in the background).
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "tokens"

    public init(service: String = "ai.miranote.accounts") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> AccountTokens? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AccountTokens.self, from: data)
    }

    public func save(_ tokens: AccountTokens?) {
        SecItemDelete(query as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// Tests and -UITEST: nothing leaves the process.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AccountTokens?

    public init(_ tokens: AccountTokens? = nil) {
        self.tokens = tokens
    }

    public func load() -> AccountTokens? {
        lock.lock()
        defer { lock.unlock() }
        return tokens
    }

    public func save(_ tokens: AccountTokens?) {
        lock.lock()
        defer { lock.unlock() }
        self.tokens = tokens
    }
}

// MARK: - The accounts service

public protocol AccountsAPI: Sendable {
    func signIn(identityToken: String, nonce: String) async throws -> AccountTokens
    func refresh(refreshToken: String) async throws -> AccountTokens
    func signOut(refreshToken: String) async throws
}

/// The accounts service (miranote-api `poc/accounts`): `/auth/apple`,
/// `/auth/refresh`, `/auth/signout`. No beta token: the service checks
/// its own credentials.
public struct LiveAccountsAPI: AccountsAPI {
    private let baseURL: URL
    private let client: HTTPClient
    private let now: @Sendable () -> Date

    public init(
        // Not configured, nobody is asked to sign in, so this is never
        // called; the beta address is only a placeholder.
        baseURL: URL = MiraNoteConfig.Backend.accountsBaseURL ?? MiraNoteConfig.Backend.Beta.accounts,
        client: HTTPClient = HTTPClient(betaToken: nil),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.client = client
        self.now = now
    }

    private struct AppleBody: Encodable {
        let identityToken: String
        let nonce: String

        enum CodingKeys: String, CodingKey {
            case identityToken = "identity_token", nonce
        }
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct Pair: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let userID: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token"
            case expiresIn = "expires_in", userID = "user_id"
        }
    }

    public func signIn(identityToken: String, nonce: String) async throws -> AccountTokens {
        let pair: Pair = try await client.postJSON(
            to: baseURL.appendingPathComponent("auth/apple"),
            body: AppleBody(identityToken: identityToken, nonce: nonce)
        )
        return tokens(pair)
    }

    public func refresh(refreshToken: String) async throws -> AccountTokens {
        let pair: Pair = try await client.postJSON(
            to: baseURL.appendingPathComponent("auth/refresh"),
            body: RefreshBody(refreshToken: refreshToken)
        )
        return tokens(pair)
    }

    public func signOut(refreshToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/signout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshBody(refreshToken: refreshToken))
        _ = try await client.send(request)
    }

    private func tokens(_ pair: Pair) -> AccountTokens {
        AccountTokens(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            userID: pair.userID,
            accessExpiresAt: now().addingTimeInterval(TimeInterval(pair.expiresIn))
        )
    }
}
