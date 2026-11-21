import Foundation
@testable import MiraNoteKit

// The account doubles, shared by AccountTests and AccountDeletionTests.

final class FakeApple: AppleCredentialProvider, @unchecked Sendable {
    private let error: Error?
    var nonceHashes: [String] = []
    var codesGiven = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func identityToken(nonceHash: String) async throws -> String {
        nonceHashes.append(nonceHash)
        if let error { throw error }
        return "apple-identity-token"
    }

    func authorizationCode() async throws -> String {
        codesGiven += 1
        if let error { throw error }
        return "apple-code-\(codesGiven)"
    }
}

final class FakeAccountsAPI: AccountsAPI, @unchecked Sendable {
    var signInResult: AccountTokens?
    var refreshResults: [Result<AccountTokens, Error>]
    var refreshDelay: UInt64 = 0
    /// What a refresh cancelled during its delay throws; nil is the
    /// `CancellationError` itself.
    var cancelledRefreshError: Error?
    var signOutError: Error?
    var deleteResult: Result<Bool, Error> = .success(true)
    var deletes: [(accessToken: String, authorizationCode: String)] = []
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
        if refreshDelay > 0 {
            do { try await Task.sleep(nanoseconds: refreshDelay) } catch { throw cancelledRefreshError ?? error }
        }
        return try refreshResults.removeFirst().get()
    }

    func signOut(refreshToken: String) async throws {
        signOuts.append(refreshToken)
        if let signOutError { throw signOutError }
    }

    func deleteAccount(accessToken: String, authorizationCode: String) async throws -> Bool {
        deletes.append((accessToken, authorizationCode))
        return try deleteResult.get()
    }
}
