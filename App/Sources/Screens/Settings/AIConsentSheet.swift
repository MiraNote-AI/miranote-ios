import MiraNoteKit
import SwiftUI
import UIKit

/// "How Mira uses AI" (#151, App Store Review Guideline 5.1.2(i)): shown
/// once, right before the first action that would send page content to
/// the server, never at launch. What is sent, to whom (Details) and what
/// is kept, then Continue or Not now. docs/privacy/ai-data.md is the
/// source of every line here.
struct AIConsentSheet: View {
    var onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How Mira uses AI")
                        .font(Sans.font(size: 26, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("aiConsent.title")
                    AIDataSummary()
                    AIDataDetails()
                    Text("Not now cancels only this action. Everything that runs on your phone keeps working.")
                        .font(Sans.font(size: 13, weight: 500))
                        .lineSpacing(AIDataLines.spacing(for: 13))
                        .foregroundStyle(SettingsStyle.value)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            VStack(spacing: 10) {
                Button { onAnswer(true) } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPill())
                .accessibilityIdentifier("aiConsent.continue")
                Button { onAnswer(false) } label: {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftPill())
                .accessibilityIdentifier("aiConsent.notNow")
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, SettingsStyle.inset)
        .background(Palette.paper.ignoresSafeArea())
    }
}

/// Body lines of this explanation, about 1.4x their size apart: Chinese
/// set at Josefin's 1.0 em line box was cramped.
enum AIDataLines {
    static func spacing(for size: CGFloat) -> CGFloat { (size * 0.3).rounded() }
}

/// What is sent and what is kept: the sheet's and Settings' first lines.
struct AIDataSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("""
                Some features need AI that does not run on your phone. When you use one, MiraNote sends what it \
                needs to our server, which passes it to the AI providers we use.
                """)
                .font(Sans.font(size: 15, weight: 500))
                .lineSpacing(AIDataLines.spacing(for: 15))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            point("What is sent", """
                The words on your page, photos you choose, and your voice when you dictate. Saved pages' words \
                are also read for a mood that colors their star.
                """)
            point("What we keep", """
                Our server keeps no words, photos or voice after the result is made, except: Mira chats and \
                photo-memory jobs for up to 1 hour, a photo-memory log for up to 7 days, and names of cut-out \
                objects in server logs.
                """)
        }
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

/// "Details": each feature, what it sends and the provider that gets it.
/// Closed until tapped.
struct AIDataDetails: View {
    /// Its accessibility identifiers' prefix: the sheet's, or Settings'.
    var idPrefix = "aiConsent"
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Details")
                        .font(Sans.font(size: 15, weight: 700))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Image("row.chevron")
                        .renderingMode(.template)
                        .foregroundStyle(SettingsStyle.value)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? Text("Shown") : Text("Hidden"))
            .accessibilityIdentifier("\(idPrefix).details")
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    row("Clean, Expand, Polish, Shorten and moods", "Your words, to DeepSeek.")
                    row("Mira chat", """
                        Your message, the page you are on and pages that match it, to DeepSeek. When Mira looks \
                        at your page, a picture of it goes to Google (Gemini). Pictures Mira makes or edits go \
                        to the providers below.
                        """)
                    row("Voice typing", """
                        Your recording is written down by Whisper on our server. The words then go to Alibaba Cloud \
                        (Qwen, China) to fix mistakes.
                        """)
                    row("Stickers, backgrounds and pictures", """
                        What you ask for, to Alibaba Cloud (Qwen and Z-Image, China).
                        """)
                    row("Photo edits", """
                        The photo and your instruction, to Google (Gemini). A cutout of something you name sends the \
                        photo to Gemini to find it; the name stays in our server log.
                        """)
                    row("Photos on a page", """
                        Each photo you add is described by Google (Gemini) so Mira can talk about it.
                        """)
                    row("Photo memories (beta)", """
                        Has its own switch. Up to 10 photos with when and roughly where they were taken, to Alibaba \
                        Cloud (Qwen, China). What the AI wrote about them is kept for 7 days.
                        """)
                    row("On your phone", "Plain cutouts and outlines never leave your phone.")
                }
                .accessibilityIdentifier("\(idPrefix).detailsList")
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Sans.font(size: 14, weight: 700))
                .foregroundStyle(Palette.ink)
            Text(text)
                .font(Sans.font(size: 13, weight: 500))
                .lineSpacing(AIDataLines.spacing(for: 13))
                .foregroundStyle(SettingsStyle.value)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shows `AIConsentSheet` over whatever is on screen -- Home, the editor's
/// cover, a sheet inside it -- when `AIConsent` asks. A sheet of its own
/// rather than a SwiftUI `.sheet`, which only its presenter's top level
/// could show. It closes before the answer goes back, so the action that
/// was waiting can present what it needs.
@MainActor
enum AIConsentPresenter {
    static func install(_ consent: AIConsent) {
        consent.present = { show(consent) }
    }

    private static func show(_ consent: AIConsent) {
        guard let top = topController() else {
            consent.answer(false)
            return
        }
        weak var shown: UIViewController?
        let sheet = AIConsentSheet { granted in
            guard let shown else { return consent.answer(granted) }
            shown.dismiss(animated: true) { consent.answer(granted) }
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

    /// The controller on top of the key window: where a sheet goes.
    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}
