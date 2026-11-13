import AuthenticationServices
import MiraNoteKit
import SwiftUI
import UIKit

/// "Sign in to use Mira's AI" (api #95 step 2): shown right after the AI
/// consent sheet, before the first action that needs our server's AI, and
/// from Settings. Sign in with Apple only; Apple is asked for no email and
/// no name. Not now cancels only the action that asked.
struct SignInSheet: View {
    var account: Account
    var onDone: (Bool) -> Void

    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sign in to use Mira's AI")
                        .font(Sans.font(size: 26, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("signIn.title")
                    Text("Mira's AI runs on our server, so it needs an account. Sign in with Apple once on this phone.")
                        .font(Sans.font(size: 15, weight: 500))
                        .lineSpacing(AIDataLines.spacing(for: 15))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    point("What we get", "An account id from Apple. Not your email, not your name.")
                    point("What stays on your phone", "Your pages, photos and voice. Signing in uploads none of them.")
                    Text("Not now cancels only this action. Everything that runs on your phone keeps working.")
                        .font(Sans.font(size: 13, weight: 500))
                        .lineSpacing(AIDataLines.spacing(for: 13))
                        .foregroundStyle(SettingsStyle.value)
                        .fixedSize(horizontal: false, vertical: true)
                    if failed {
                        Text("Could not sign in. Check your connection and try again.")
                            .font(Sans.font(size: 14, weight: 600))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("signIn.error")
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            VStack(spacing: 10) {
                AppleIDButton(action: signIn)
                    .frame(height: 50)
                    .disabled(busy)
                Button { onDone(false) } label: {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftPill())
                .disabled(busy)
                .accessibilityIdentifier("signIn.notNow")
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, SettingsStyle.inset)
        .background(Palette.paper.ignoresSafeArea())
    }

    private func point(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Sans.font(size: 15, weight: 700))
                .foregroundStyle(Palette.ink)
            Text(text)
                .font(Sans.font(size: 14, weight: 500))
                .lineSpacing(AIDataLines.spacing(for: 14))
                .foregroundStyle(SettingsStyle.intro)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Closing Apple's own sheet is not a failure: the writer is back here
    /// and can try again or say Not now.
    private func signIn() {
        guard !busy else { return }
        busy = true
        failed = false
        Task {
            do {
                try await account.signIn()
                onDone(true)
            } catch AppleSignInError.cancelled {
                busy = false
            } catch {
                busy = false
                failed = true
            }
        }
    }
}

/// Apple's own Sign in with Apple button (the App Review guidelines want
/// it, not a look-alike). It follows the system language.
private struct AppleIDButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: .black)
        button.cornerRadius = 25
        button.accessibilityIdentifier = "signIn.apple"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Shows `SignInSheet` over whatever is on screen when `Account` asks,
/// the same way `AIConsentPresenter` shows the consent sheet. It closes
/// before the answer goes back, so the waiting action can present what it
/// needs.
@MainActor
enum SignInPresenter {
    static func install(_ account: Account, consent: AIConsent) {
        account.present = { show(account) }
        consent.signIn = { await account.permit() }
    }

    private static func show(_ account: Account) {
        guard let top = AIConsentPresenter.topController() else {
            account.answer(false)
            return
        }
        weak var shown: UIViewController?
        let sheet = SignInSheet(account: account) { signedIn in
            guard let shown else { return account.answer(signedIn) }
            shown.dismiss(animated: true) { account.answer(signedIn) }
        }
        .environment(\.locale, AppSettings.shared.language.locale)
        let host = UIHostingController(rootView: sheet)
        host.view.backgroundColor = UIColor(Palette.paper)
        // A choice, not a swipe: Not now is one tap away.
        host.isModalInPresentation = true
        host.modalPresentationStyle = .pageSheet
        host.sheetPresentationController?.detents = [.large()]
        shown = host
        top.present(host, animated: true)
    }
}

/// Apple's sign-in sheet through AuthenticationServices. Asks for no
/// scopes: we keep no email or name (design 3.1).
@MainActor
final class LiveAppleCredentialProvider: NSObject, AppleCredentialProvider {
    private var pending: CheckedContinuation<String, Error>?
    private var controller: ASAuthorizationController?

    func identityToken(nonceHash: String) async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = nonceHash
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            pending?.resume(throwing: AppleSignInError.cancelled)
            pending = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        pending?.resume(with: result)
        pending = nil
        controller = nil
    }
}

extension LiveAppleCredentialProvider: ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8)
        else { return finish(.failure(AppleSignInError.noIdentityToken)) }
        finish(.success(token))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            return finish(.failure(AppleSignInError.cancelled))
        }
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        AIConsentPresenter.topController()?.view.window ?? ASPresentationAnchor()
    }
}

extension Account {
    /// The app's one account. UI tests get mocks for Apple and the accounts
    /// service and start signed in, so suites that are not about sign-in
    /// are never stopped by it -- unless they launch with `-SIGN-IN-ASK`.
    static let shared: Account = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST") {
            let signedIn = !arguments.contains("-SIGN-IN-ASK")
            return Account(store: InMemoryTokenStore(signedIn ? UITestAccounts.tokens() : nil),
                           api: UITestAccounts(), apple: UITestApple())
        }
        #endif
        return Account(store: freshInstallStore(), api: LiveAccountsAPI(), apple: LiveAppleCredentialProvider())
    }()

    /// Keychain items outlive the app: a reinstall would come back signed
    /// in as whoever used it before. The first launch of an install
    /// forgets them.
    private static func freshInstallStore() -> KeychainTokenStore {
        let store = KeychainTokenStore()
        let key = "miranote.accounts.installed"
        if !UserDefaults.standard.bool(forKey: key) {
            store.save(nil)
            UserDefaults.standard.set(true, forKey: key)
        }
        return store
    }
}

#if DEBUG
/// -UITEST: Apple says yes at once.
private struct UITestApple: AppleCredentialProvider {
    func identityToken(nonceHash: String) async throws -> String { "uitest-identity-token" }
}

/// -UITEST: the accounts service, answering every call.
private struct UITestAccounts: AccountsAPI {
    static func tokens() -> AccountTokens {
        AccountTokens(accessToken: "uitest-access", refreshToken: "uitest-refresh", userID: "uitest-user",
                      accessExpiresAt: Date().addingTimeInterval(3600))
    }

    func signIn(identityToken: String, nonce: String) async throws -> AccountTokens { Self.tokens() }
    func refresh(refreshToken: String) async throws -> AccountTokens { Self.tokens() }
    func signOut(refreshToken: String) async throws {}
}
#endif
