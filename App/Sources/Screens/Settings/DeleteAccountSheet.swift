import MiraNoteKit
import SwiftUI

/// Settings > Account > Delete account (api #95 step 6, Guideline
/// 5.1.1(v)): what is deleted and what stays, that deleting does not
/// cancel a subscription (with Apple's page to manage it), a confirmation,
/// then Sign in with Apple and `DELETE /me` (`AccountDeletion`). Pages are
/// never touched.
struct DeleteAccountSheet: View {
    var account: Account
    var onClose: () -> Void

    @State private var deletion: AccountDeletion
    @State private var confirming = false

    init(account: Account, onClose: @escaping () -> Void) {
        self.account = account
        self.onClose = onClose
        _deletion = State(initialValue: AccountDeletion(account: account))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if case .deleted(let appleRevoked) = deletion.state {
                        done(appleRevoked: appleRevoked)
                    } else {
                        explanation
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            buttons
                .padding(.bottom, 12)
        }
        .padding(.horizontal, SettingsStyle.inset)
        .background(Palette.paper.ignoresSafeArea())
        .interactiveDismissDisabled(deletion.state == .deleting)
        .alert("Delete your account?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deletion.delete() } }
        } message: {
            Text("This cannot be undone. Sign in with Apple asks you to confirm next.")
        }
        // The outcome replaces the explanation or adds a line under it,
        // and nothing moves VoiceOver there: say it, as SaveToast does.
        .onChange(of: deletion.state) { _, state in
            switch state {
            case .deleted:
                AccessibilityNotification.Announcement(String(appCopy: "Your account is deleted")).post()
            case .failed(let failure):
                AccessibilityNotification.Announcement(failure.localizedDescription).post()
            case .ready, .deleting:
                break
            }
        }
    }

    @ViewBuilder private var explanation: some View {
        title("Delete your account")
        point("What is deleted",
              "Your MiraNote account and your Sign in with Apple link to MiraNote.")
        // The server keeps ai_usage rows with user_id set to null (api #116).
        point("What is kept", "Your AI usage records stop being linked to you.")
        point("What stays",
              "Your pages, photos and voice stay on this phone. Deleting your account removes none of them.")
        VStack(alignment: .leading, spacing: 4) {
            point("Your subscription", """
            Deleting your account does not cancel MiraNote Plus. If you subscribe, Apple keeps billing you \
            until you cancel in your Apple Account settings.
            """)
            Link("Manage subscriptions", destination: MiraNoteConfig.Legal.manageSubscriptions)
                .font(Sans.font(size: 15, weight: 600))
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
                .accessibilityIdentifier("deleteAccount.manageSubscriptions")
        }
        if case .failed(let failure) = deletion.state {
            Text(failure.localizedDescription)
                .font(Sans.font(size: 14, weight: 600))
                .lineSpacing(AIDataLines.spacing(for: 14))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("deleteAccount.error")
        }
    }

    @ViewBuilder private func done(appleRevoked: Bool) -> some View {
        title("Your account is deleted")
            .accessibilityIdentifier("deleteAccount.done")
        line("Your pages are still on this phone. Mira's AI asks you to sign in again, with a new account.")
        if !appleRevoked {
            line("""
            To also remove MiraNote from Sign in with Apple, open the Settings app, tap your name, then \
            Sign-In & Security, then Sign in with Apple.
            """)
            .accessibilityIdentifier("deleteAccount.appleNotRevoked")
        }
        line("A MiraNote Plus subscription continues until you cancel it in your Apple Account settings.")
    }

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 10) {
            if case .deleted = deletion.state {
                Button(action: onClose) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPill())
                .accessibilityIdentifier("deleteAccount.close")
            } else {
                // Signed out, a try cannot reach the server: the copy says
                // to sign in again first.
                if deletion.state != .failed(.signedOut) {
                    Button { confirming = true } label: {
                        Group {
                            if deletion.state == .deleting {
                                ProgressView()
                                    .accessibilityLabel("Deleting your account")
                            } else {
                                Text(isFailed ? "Try again" : "Delete account")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryPill())
                    .disabled(deletion.state == .deleting)
                    .accessibilityIdentifier("deleteAccount.delete")
                }
                Button(action: onClose) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftPill())
                .disabled(deletion.state == .deleting)
                .accessibilityIdentifier("deleteAccount.cancel")
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = deletion.state { return true }
        return false
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Sans.font(size: 26, weight: 600))
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func line(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Sans.font(size: 15, weight: 500))
            .lineSpacing(AIDataLines.spacing(for: 15))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
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
}
