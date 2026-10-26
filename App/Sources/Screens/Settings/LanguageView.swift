import MiraNoteKit
import SwiftUI

/// Handoff screen 05: English and Simplified Chinese as single-choice cards
/// with their flags. The choice is stored and shown here and on Settings;
/// the zh-CN copy itself comes in a follow-up PR.
struct LanguageView: View {
    var settings: AppSettings
    var onBack: () -> Void = {}

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsEyebrow(text: "APP LANGUAGE")
                Text("Choose the language used in MiraNote.")
                    .font(Sans.font(size: 15, weight: 500))
                    .foregroundStyle(SettingsStyle.intro)
                    .padding(.top, 9)
                VStack(spacing: 14) {
                    ForEach(LanguageChoice.allCases, id: \.self) { choice in
                        option(choice)
                    }
                }
                .padding(.top, 26)
                Text("You can change this anytime in Settings.")
                    .font(Sans.font(size: 13, weight: 500))
                    .foregroundStyle(SettingsStyle.note)
                    .padding(.top, 39)
            }
            .padding(.horizontal, SettingsStyle.inset)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsHeader(title: "Language", onBack: onBack)
        }
    }

    /// A 100 pt card: the 30 x 20 flag 20 in, the name (SemiBold 19) over
    /// the locale (Medium 13) 17 to its right, the radio 24 in from the
    /// right edge.
    private func option(_ choice: LanguageChoice) -> some View {
        let isOn = settings.language == choice
        return Button {
            settings.language = choice
        } label: {
            HStack(spacing: 17) {
                Image(choice.flag)
                    .resizable()
                    .frame(width: 30, height: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                        .font(Sans.font(size: 19, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 27)
                    Text(choice.subtitle)
                        .font(Sans.font(size: 13, weight: 500))
                        .foregroundStyle(SettingsStyle.note)
                        .frame(minHeight: 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsRadio(isOn: isOn)
            }
            .padding(.leading, 20)
            .padding(.trailing, 24)
            .padding(.vertical, 12)
            .frame(minHeight: 100)
            .settingsCard(selected: isOn)
            .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.cardCorner))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.flagName), \(choice.title), \(choice.subtitle)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("language.\(choice.rawValue)")
    }
}

private extension LanguageChoice {
    var flag: String {
        switch self {
        case .english: return "flag.us"
        case .simplifiedChinese: return "flag.cn"
        }
    }

    /// The flag for VoiceOver; the name and locale carry the meaning.
    var flagName: String {
        switch self {
        case .english: return "United States flag"
        case .simplifiedChinese: return "China flag"
        }
    }
}
