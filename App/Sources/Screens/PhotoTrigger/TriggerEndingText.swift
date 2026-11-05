import MiraNoteKit
import SwiftUI

/// The ending page's words under the risen card, fading in one after
/// another: the fact line (date and place only), the detail line in a face
/// of its own (no row at all when there is none), the question, and the
/// button that keeps the day (handoff 7.7).
struct TriggerEndingText: View {
    /// The detail line's face, shared with the canvas draft's detail block:
    /// an on-demand Chinese serif (`DetailFont`), the system font until it
    /// has downloaded.
    nonisolated static var detailFont: String { DetailFont.currentName }
    nonisolated static let detailSize: CGFloat = 18
    static let gapAbove: CGFloat = 22
    static let gapBelow: CGFloat = 20
    static let minSpacer: CGFloat = 16

    /// The height under the card that words and a button `content` tall
    /// take, the gaps and the home indicator's inset included.
    static func room(content: CGFloat, bottomInset: CGFloat) -> CGFloat {
        gapAbove + content + minSpacer + gapBelow + bottomInset
    }

    let ending: TriggerMemory.Ending
    let shown: Bool
    /// The settled card's bottom edge, in screen coordinates.
    let top: CGFloat
    let insets: EdgeInsets
    /// The draft is being made: the button waits (no second draft).
    var keeping = false
    /// The words and the button, measured: their height together.
    @Binding var measured: CGFloat
    var onKeep: () -> Void

    @State private var wordsHeight: CGFloat = 0
    @State private var buttonHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            words
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    wordsHeight = $0
                    measured = wordsHeight + buttonHeight
                }

            Spacer(minLength: Self.minSpacer)

            Button(action: onKeep) {
                Text(ending.ctaLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryPill(verticalPadding: 16))
            .disabled(keeping)
            .modifier(Entrance(shown: shown, delay: 0.35))
            .accessibilityIdentifier("trigger.keep")
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                buttonHeight = $0
                measured = wordsHeight + buttonHeight
            }
        }
        .padding(.top, top + Self.gapAbove)
        .padding(.bottom, insets.bottom + Self.gapBelow)
        .padding(.horizontal, 32)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }

    private var words: some View {
        VStack(spacing: 0) {
            Text(ending.factLine)
                .font(Sans.font(size: 14, weight: 500))
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
                .modifier(Entrance(shown: shown, delay: 0))
                .padding(.bottom, 14)
                .accessibilityIdentifier("trigger.factLine")

            if !ending.detail.isEmpty {
                Text(ending.detail)
                    .font(Font(DetailFont.uiFont(named: Self.detailFont, size: Self.detailSize)))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(Entrance(shown: shown, delay: 0.1))
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("trigger.detail")
            }

            Text(ending.question)
                .font(Font(QuestionFont.uiFont(size: 22)))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Entrance(shown: shown, delay: 0.2))
                .accessibilityIdentifier("trigger.question")
        }
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
