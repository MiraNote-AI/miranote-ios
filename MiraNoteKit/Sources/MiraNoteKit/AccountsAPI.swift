import Foundation

public protocol AccountsAPI: Sendable {
    func signIn(identityToken: String, nonce: String) async throws -> AccountTokens
    func refresh(refreshToken: String) async throws -> AccountTokens
    func signOut(refreshToken: String) async throws
    /// `DELETE /me`. True when Apple revoked the link too; false when the
    /// account is deleted but Apple refused or was not asked (502/503).
    func deleteAccount(accessToken: String, authorizationCode: String) async throws -> Bool
}

/// The accounts service (miranote-api `poc/accounts`): `/auth/apple`,
/// `/auth/refresh`, `/auth/signout`, `DELETE /me`. No beta token: the service checks
/// its own credentials.
public struct LiveAccountsAPI: AccountsAPI {
    private let baseURL: URL
    private let client: HTTPClient
    private let now: @Sendable () -> Date

    public init(
        // Not configured, nobody is asked to sign in, so this is never
        // called; the beta address is only a placeholder.
        baseURL: URL = MiraNoteConfig.Backend.accountsBaseURL ?? MiraNoteConfig.Backend.Beta.accounts,
        client: HTTPClient = HTTPClient(betaToken: nil, userTokens: nil),
        now: @escaping @Sendable () -> Date = { Date() }
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

    private struct DeleteBody: Encodable {
        let authorizationCode: String

        enum CodingKeys: String, CodingKey {
            case authorizationCode = "authorization_code"
        }
    }

    private struct Deleted: Decodable {
        let deleted: Bool
        let appleRevoked: Bool

        enum CodingKeys: String, CodingKey {
            case deleted, appleRevoked = "apple_revoked"
        }
    }

    public func deleteAccount(accessToken: String, authorizationCode: String) async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("me"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(DeleteBody(authorizationCode: authorizationCode))
        let data: Data
        do {
            data = try await client.send(request)
        } catch BackendError.server(let status, let detail) where status == 502 || status == 503 {
            // Our data is deleted; only Apple's side failed.
            guard let body = detail.flatMap({ $0.data(using: .utf8) }),
                  (try? JSONDecoder().decode(Deleted.self, from: body))?.deleted == true
            else { throw BackendError.server(status: status, detail: detail) }
            return false
        }
        guard let answer = try? JSONDecoder().decode(Deleted.self, from: data), answer.deleted else {
            throw BackendError.decoding
        }
        return answer.appleRevoked
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
