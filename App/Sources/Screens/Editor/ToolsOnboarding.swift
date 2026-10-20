import MiraNoteKit
import SwiftUI

/// The first-run editor introduction (handoff screen 03), a full editor
/// state rather than an overlay: Back / undo / Next on top, this card in the
/// canvas card's slot, no tool bar, and a "Choose your background / Go" bar
/// in the composer's place. Shown once, on the first blank page.
///
/// The card shows the five tools as the icon-only strip they become, then
/// one row each; tapping either opens that tool.
struct ToolsOnboarding: View {
    var onPick: (EditorMode) -> Void

    static let hintID = "editor-tools"

    private static let details: [(EditorMode, String)] = [
        (.background, "Paper, palettes & font pairings"),
        (.voice, "Record and place sound"),
        (.text, "Write, style & arrange"),
        (.image, "Add and edit photos"),
        (.sticker, "Decorate your memory"),
    ]

    private static let secondary = Color(hex: 0x777267)
    private static let rowBorder = Color(hex: 0xE8E4D9)

    var body: some View {
        // Card-relative frames from the handoff: content inset 23, eyebrow
        // at 26, title 53, subtitle 82, strip 116, "Tap an icon" 197, rows
        // from 223 at a 57 pt pitch. Josefin's line box is 1.0 em, so the
        // gaps below are the frame gaps.
        VStack(alignment: .leading, spacing: 0) {
            Text("FIVE CREATIVE TOOLS")
                .font(Sans.font(size: 12, weight: 600))
                .foregroundStyle(Color(hex: 0x877862))
                .padding(.bottom, 17)
            Text("Create your way")
                .font(Sans.font(size: 22, weight: 700))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 7)
            Text("These icons stay with you on every page.")
                .font(Sans.font(size: 14, weight: 500))
                .foregroundStyle(Self.secondary)
                .padding(.bottom, 22)
            strip
                .padding(.bottom, 19)
            Text("Tap an icon to switch tools")
                .font(Sans.font(size: 14, weight: 600))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 14)
            VStack(spacing: 6) {
                ForEach(Self.details, id: \.0) { mode, detail in
                    row(mode, detail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .padding(.horizontal, 23)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onboardingCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.tools")
    }

    /// The tool bar as it will look, icons only: a 62 pt #F1F0E7 tray with
    /// five 40 pt tiles at a 56 pt pitch, Background lit.
    private var strip: some View {
        HStack(spacing: 16) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    onPick(mode)
                } label: {
                    icon(mode)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(mode == .background ? Palette.selectedTool : Color.white)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityIdentifier("onboarding.icon.\(mode.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xF1F0E7)))
    }

    private func row(_ mode: EditorMode, _ detail: String) -> some View {
        Button {
            onPick(mode)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                icon(mode)
                    .frame(width: 35, height: 35)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(mode == .background ? Palette.selectedTool : Color(hex: 0xF2F1E9))
                    )
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 8) {
                    Text(mode.title)
                        .font(Sans.font(size: 14, weight: 600))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Sans.font(size: 12, weight: 500))
                        .foregroundStyle(Self.secondary)
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .frame(height: 51, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Self.rowBorder, lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.tool.\(mode.rawValue)")
    }

    private func icon(_ mode: EditorMode) -> some View {
        Image(mode.iconAsset)
            .renderingMode(.template)
            .resizable()
            .frame(width: 20, height: 20)
            .foregroundStyle(mode == .background ? Palette.onInk : Palette.toolIcon)
            .accessibilityHidden(true)
    }
}

/// The composer slot on screen 03: the glass capsule reading "Choose your
/// background" with the ink Go pill. One button, the way on to Background.
struct ToolsOnboardingBar: View {
    var onGo: () -> Void

    var body: some View {
        Button(action: onGo) {
            HStack(spacing: 8) {
                Text("Choose your background")
                    .font(.miraComposer)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Text("Go")
                    .font(.miraComposerAction)
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 52, height: 34)
                    .background(Capsule().fill(Palette.ink))
            }
            .padding(.leading, 17)
            .padding(.trailing, 19)
            .frame(height: 54)
            .background(GlassCapsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose your background")
        .accessibilityIdentifier("onboarding.background")
        .padding(.horizontal, Metrics.chromeInset)
    }
}

private extension View {
    /// The canvas card's frame and shadow, filled white@0.64 as on screen 03.
    func onboardingCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.canvasCorner)
        return frame(maxWidth: .infinity)
            .background(shape.fill(Color.white.opacity(0.64)))
            .overlay(shape.strokeBorder(Palette.ink.opacity(0.06), lineWidth: Metrics.hairline))
            .background(shape.fill(Palette.paper).shadow(color: Palette.ink.opacity(0.08), radius: 19, y: 16))
            .padding(.horizontal, Metrics.canvasInset)
    }
}
