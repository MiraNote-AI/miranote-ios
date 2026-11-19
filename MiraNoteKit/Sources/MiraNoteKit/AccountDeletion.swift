import Foundation
import Observation

/// Settings > Delete account (api #95 step 6, Guideline 5.1.1(v)): the
/// sheet's state. `delete()` runs once the writer confirmed: Apple
/// confirms it is them, the server deletes the account, and the phone
/// forgets our tokens (`Account.deleteAccount()`). Pages stay on the
/// phone whatever happens. Closing Apple's sheet goes back to `ready`.
@MainActor
@Observable
public final class AccountDeletion {
    public enum State: Equatable {
        /// What is deleted and what is kept, and the Delete button.
        case ready
        /// Apple's sheet is up, or the request is out.
        case deleting
        /// Done. `appleRevoked` false: the account is gone, but the writer
        /// should remove MiraNote from Sign in with Apple themselves.
        case deleted(appleRevoked: Bool)
        /// Not deleted (or not known to be): the reason, and Try again.
        case failed(Failure)
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case offline
        /// The request went out but no answer came back.
        case timedOut
        /// Our sign-in had ended (a 401). The server also answers 401 once
        /// the account is marked deleted, so it may already be gone: an
        /// earlier try whose answer was lost, or another device. Sign in,
        /// then delete.
        case signedOut
        /// Apple's sheet failed: nothing was sent.
        case apple
        case server

        init(_ error: Error) {
            switch error {
            case BackendError.unreachable: self = .offline
            case BackendError.timedOut: self = .timedOut
            case AccountError.signedOut: self = .signedOut
            case is BackendError: self = .server
            default: self = .apple
            }
        }

        public var errorDescription: String? {
            switch self {
            case .offline:
                return String(appCopy: "You're offline, so nothing was deleted. Connect to the internet and try again.")
            case .timedOut:
                return String(appCopy: """
                    MiraNote did not answer in time, so your account may not be deleted. Try again.
                    """)
            case .signedOut:
                return String(appCopy: """
                    Your sign-in has ended, so MiraNote cannot tell whether your account is already deleted. \
                    Sign in again, then delete your account.
                    """)
            case .apple:
                return String(appCopy: """
                    Sign in with Apple did not confirm it's you, so nothing was deleted. Try again.
                    """)
            case .server:
                return String(appCopy: "Your account could not be deleted. Try again later.")
            }
        }
    }

    public private(set) var state: State = .ready

    @ObservationIgnored private let account: Account

    public init(account: Account) {
        self.account = account
    }

    public func delete() async {
        switch state {
        case .ready, .failed: break
        case .deleting, .deleted: return
        }
        state = .deleting
        do {
            state = .deleted(appleRevoked: try await account.deleteAccount())
        } catch AppleSignInError.cancelled {
            state = .ready
        } catch {
            state = .failed(Failure(error))
        }
    }
}
