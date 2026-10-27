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
/// over the paper.
struct SettingsHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Image("nav.back")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Palette.ink)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .circleHitTarget()
            .accessibilityLabel("Back")
            .accessibilityIdentifier("settings.back")

            Text(title)
                .font(Sans.font(size: 26, weight: 600))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsStyle.inset)
        .padding(.bottom, 8)
        .background(Palette.paper)
    }
}

/// A section label above a card: "PREFERENCES" (Bold 12, 1.5 tracking) or
/// "CHOOSE YOUR LOOK" (Bold 13).
struct SettingsEyebrow: View {
    let text: String
    var size: CGFloat = 13
    var tracking: CGFloat = 0

    var body: some View {
        Text(text)
            .font(Sans.font(size: size, weight: 700))
            .tracking(tracking)
            .foregroundStyle(SettingsStyle.eyebrow)
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
    /// shadow.
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
    }

    /// The 38 pt glass circle of Home's header and the back button.
    func glassCircle() -> some View {
        frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.58))
                    .overlay(Circle().strokeBorder(Color(hex: 0x48433B).opacity(0.12), lineWidth: 1))
                    .shadow(color: Color(hex: 0x544738).opacity(0.025), radius: 8, y: 6)
            )
    }

    /// A 38 pt circle taps as a 44 x 44 box without moving its neighbours.
    func circleHitTarget() -> some View {
        padding(3)
            .contentShape(Rectangle())
            .padding(-3)
    }
}

extension AppearanceChoice {
    var title: String {
        switch self {
        case .system: return "System"
        case .forest: return "Forest"
        case .sunlitPop: return "Sunlit Pop"
        }
    }
}

extension LanguageChoice {
    /// The language in its own words. The Chinese strings are written as
    /// escapes (committed text stays ASCII): they read "Chinese" and
    /// "Simplified Chinese (China)".
    var title: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "\u{4E2D}\u{6587}"
        }
    }

    var subtitle: String {
        switch self {
        case .english: return "English (United States)"
        case .simplifiedChinese: return "\u{7B80}\u{4F53}\u{4E2D}\u{6587}\u{FF08}\u{4E2D}\u{56FD}\u{FF09}"
        }
    }
}
