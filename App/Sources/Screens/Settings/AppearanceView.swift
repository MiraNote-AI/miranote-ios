import MiraNoteKit
import SwiftUI

/// Handoff screen 04: System, Forest and Sunlit Pop as single-choice cards
/// with a Home thumbnail each. The choice is stored and applied app-wide
/// at once (`Theme`, from `HomeFlow`).
struct AppearanceView: View {
    var settings: AppSettings
    var onBack: () -> Void = {}

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsEyebrow(text: "CHOOSE YOUR LOOK")
                Text("Make MiraNote feel like yours.")
                    .font(Sans.font(size: 15, weight: 500))
                    .foregroundStyle(theme.muted(SettingsStyle.intro))
                    .padding(.top, 9)
                VStack(spacing: 15) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                        option(choice)
                    }
                }
                .padding(.top, 26.5)
                Text("Your choice sets the app\u{2019}s colors and typography.")
                    .font(Sans.font(size: 13, weight: 500))
                    .foregroundStyle(theme.muted(SettingsStyle.note))
                    .padding(.top, 35.5)
            }
            .padding(.horizontal, SettingsStyle.inset)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsHeader(title: "Appearance", onBack: onBack)
        }
    }

    /// A 144 pt card: the 82 x 122 Home thumbnail at (15, 11), name
    /// (SemiBold 18), description (Medium 13) and state (Medium 12) 18 to
    /// its right, the radio 26 in from the right edge.
    private func option(_ choice: AppearanceChoice) -> some View {
        let isOn = settings.appearance == choice
        return Button {
            settings.appearance = choice
        } label: {
            HStack(alignment: .top, spacing: 18) {
                Image("appearance.\(choice.rawValue)")
                    .resizable()
                    .frame(width: 82, height: 122)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(hex: 0xD8D5C9), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 0) {
                    Text(choice.title)
                        .font(Sans.font(size: 18, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 26)
                    Text(choice.blurb)
                        .font(Sans.font(size: 13, weight: 500))
                        .foregroundStyle(SettingsStyle.note)
                        .frame(minHeight: 20)
                        .padding(.top, 8)
                    Text(isOn ? "Selected" as LocalizedStringKey : "Tap to select")
                        .font(Sans.font(size: 12, weight: 500))
                        .foregroundStyle(isOn ? SettingsStyle.intro : Color(hex: 0xA49A8C))
                        .frame(minHeight: 18)
                        .padding(.top, 23)
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsRadio(isOn: isOn)
                    .padding(.top, 46)
            }
            .padding(.leading, 15)
            .padding(.trailing, 26)
            .padding(.vertical, 11)
            .frame(minHeight: 144)
            .settingsCard(selected: isOn)
            .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.cardCorner))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.title), \(choice.blurb)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("appearance.\(choice.rawValue)")
    }
}

private extension AppearanceChoice {
    var blurb: String {
        switch self {
        case .system: return String(appCopy: "Original MiraNote")
        case .forest: return String(appCopy: "Forest green \u{00B7} warm gold")
        case .sunlitPop: return String(appCopy: "Peach \u{00B7} coral \u{00B7} lilac")
        }
    }
}
