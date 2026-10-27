import MiraNoteKit
import SwiftUI

/// The pieces the Settings and Profile screens share (handoff 2026-10-24,
/// screens 03-07): the back-circle header, the section eyebrow, the warm
/// card and the radio. Values are the handoff's `layout.json`.
enum SettingsStyle {
    /// Section eyebrows (#8F8477, Home's date color).
    static let eyebrow = HomeView.dateColor
    /// Row values and the text-size "A"s: the handoff's #878476 darkened
    /// along its hue to 4.9:1 on the card (it read 3.6:1).
    static let value = Color(hex: 0x716E62)
    /// An unselected card's "Tap to select": the handoff's #A49A8C darkened
    /// along its hue to 4.9:1 on the card (it read 2.7:1).
    static let hint = Color(hex: 0x776D5E)
    /// Card subtitles, helper lines and notes.
    static let note = Color(hex: 0x8A8476)
    /// The intro line under an eyebrow and a selected card's "Selected".
    static let intro = Color(hex: 0x635B50)
    /// A selected card's border and radio.
    static let selected = Color(hex: 0x292620)
    static let cardCorner: CGFloat = 22
    static let inset: CGFloat = 24
}

/// The 38 pt glass back circle and a SemiBold 26 title, 16 apart, pinned
/// over the paper (the theme's background).
struct SettingsHeader: View {
    let title: LocalizedStringKey
    let onBack: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Image("nav.back")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(theme.ink)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .circleHitTarget()
            .accessibilityLabel("Back")
            .accessibilityIdentifier("settings.back")

            Text(title)
                .font(Sans.font(size: 26, weight: 600))
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsStyle.inset)
        .padding(.bottom, 8)
        .background(theme.background)
    }
}

/// A section label above a card: "PREFERENCES" (Bold 12, 1.5 tracking) or
/// "CHOOSE YOUR LOOK" (Bold 13).
struct SettingsEyebrow: View {
    let text: LocalizedStringKey
    var size: CGFloat = 13
    var tracking: CGFloat = 0

    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(Sans.font(size: size, weight: 700))
            .tracking(tracking)
            .foregroundStyle(theme.muted(SettingsStyle.eyebrow))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The 22 pt radio: ink ring and 8 pt dot when on, a #BFB9AC ring when off.
struct SettingsRadio: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: 0xFFFDFA))
            .overlay(Circle().strokeBorder(isOn ? SettingsStyle.selected : Color(hex: 0xBFB9AC), lineWidth: 1.5))
            .overlay {
                if isOn { Circle().fill(SettingsStyle.selected).frame(width: 8, height: 8) }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The handoff's card: #FFFDF8 at 82%, r22, a #D8D5CA@0.8 hairline
    /// (or the 1.5 pt ink border of a selected option) and a soft warm
    /// shadow. Over the paper whatever the theme: the cards and their
    /// contents keep the System colors.
    func settingsCard(selected: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: SettingsStyle.cardCorner)
                .fill(Palette.warmWhite.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsStyle.cardCorner)
                        .strokeBorder(selected ? SettingsStyle.selected : Palette.hairline.opacity(0.8),
                                      lineWidth: selected ? 1.5 : 1)
                )
                .shadow(color: Color(hex: 0x544738).opacity(0.07), radius: 12, y: 10)
        )
        .background(RoundedRectangle(cornerRadius: SettingsStyle.cardCorner).fill(Palette.paper))
    }

    /// The 38 pt glass circle of Home's header and the back button.
    func glassCircle() -> some View {
        modifier(GlassCircle())
    }

    /// A 38 pt circle taps as a 44 x 44 box without moving its neighbours.
    func circleHitTarget() -> some View {
        padding(3)
            .contentShape(Rectangle())
            .padding(-3)
    }
}

private struct GlassCircle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(theme.circleFill)
                    .overlay(Circle().strokeBorder(theme.circleStroke, lineWidth: 1))
                    .shadow(color: Color(hex: 0x544738).opacity(0.025), radius: 8, y: 6)
            )
    }
}

extension AppearanceChoice {
    var title: String {
        switch self {
        case .system: return String(appCopy: "System")
        case .forest: return String(appCopy: "Forest")
        case .sunlitPop: return String(appCopy: "Sunlit Pop")
        }
    }
}

extension LanguageChoice {
    /// The language in its own words, whatever the app's language: the
    /// Chinese names come from the catalog's zh-Hans entries.
    var title: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese:
            return String(localized: LocalizedStringResource("language.zh.title", defaultValue: "Chinese",
                                                             locale: locale))
        }
    }

    var subtitle: String {
        switch self {
        case .english: return "English (United States)"
        case .simplifiedChinese:
            return String(localized: LocalizedStringResource("language.zh.subtitle",
                                                             defaultValue: "Simplified Chinese (China)",
                                                             locale: locale))
        }
    }
}
