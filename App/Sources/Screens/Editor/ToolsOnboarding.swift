import SwiftUI

/// The first-run editor introduction (handoff screen 03): the five tools,
/// what each is for, and a way straight into the first one the handoff flow
/// visits, Background. Shown once, on the first blank page.
struct ToolsOnboarding: View {
    var onSkip: () -> Void
    var onChooseBackground: () -> Void

    static let hintID = "editor-tools"

    private static let details: [(EditorMode, String)] = [
        (.background, "Paper, palettes & font pairings"),
        (.voice, "Record and place sound"),
        (.text, "Write, style & arrange"),
        (.image, "Add and edit photos"),
        (.sticker, "Decorate your memory"),
    ]

    var body: some View {
        // A scrim owns every touch around the card: a tool tapped behind
        // it would act while the card stayed up. Tapping it is Skip.
        ZStack {
            Palette.ink.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture(perform: onSkip)
                .accessibilityHidden(true)
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FIVE CREATIVE TOOLS")
                .font(Sans.font(size: 11, weight: 600))
                .kerning(1.2)
                .foregroundStyle(Palette.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Create your way")
                    .font(.miraPageTitle)
                    .foregroundStyle(Palette.ink)
                Text("These icons stay with you on every page.")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(Self.details, id: \.0) { mode, detail in
                    row(mode, detail)
                }
            }

            HStack(spacing: 10) {
                Button("Skip", action: onSkip)
                    .buttonStyle(NavPill(prominent: false))
                    .accessibilityIdentifier("onboarding.skip")
                Spacer()
                Button("Choose your background", action: onChooseBackground)
                    .buttonStyle(NavPill(prominent: true))
                    .accessibilityIdentifier("onboarding.background")
            }
            .padding(.top, 4)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30).fill(Palette.paper.opacity(0.75)))
                .shadow(color: Palette.ink.opacity(0.12), radius: 24, y: 14)
        )
        .padding(.horizontal, Metrics.screenPadding)
        .accessibilityElement(children: .contain)
        // VoiceOver stays on the card, as touches do via the scrim.
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("onboarding.tools")
    }

    private func row(_ mode: EditorMode, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(mode.iconAsset)
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(mode == .background ? Palette.onInk : Palette.toolIcon)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(mode == .background ? Palette.selectedTool : Palette.toolSurface)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.miraCardTitle)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.warmWhite)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hairline, lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
    }
}
