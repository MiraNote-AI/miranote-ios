import MiraNoteKit
import SwiftUI

/// The ending page's words under the risen card, fading in one after
/// another: the fact line (date and place only), the question, and the
/// button that keeps the day.
struct TriggerEndingText: View {
    let ending: TriggerMemory.Ending
    let shown: Bool
    /// The settled card's bottom edge, in screen coordinates.
    let top: CGFloat
    let insets: EdgeInsets
    var onKeep: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(ending.factLine)
                .font(Sans.font(size: 14, weight: 500))
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
                .modifier(Entrance(shown: shown, delay: 0))
                .padding(.bottom, 14)

            Text(ending.question)
                // No Chinese serif ships with iOS: the serif design keeps the
                // Latin quiet and falls back to the system face for Chinese.
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Entrance(shown: shown, delay: 0.15))

            Spacer(minLength: 16)

            Button(action: onKeep) {
                Text(ending.ctaLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryPill(verticalPadding: 16))
            .modifier(Entrance(shown: shown, delay: 0.3))
            .accessibilityIdentifier("trigger.keep")
        }
        .padding(.top, top + 22)
        .padding(.bottom, insets.bottom + 20)
        .padding(.horizontal, 32)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }

    private struct Entrance: ViewModifier {
        let shown: Bool
        let delay: Double

        func body(content: Content) -> some View {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 8)
                .animation(shown ? .easeOut(duration: 0.4).delay(0.45 + delay) : nil, value: shown)
        }
    }
}
