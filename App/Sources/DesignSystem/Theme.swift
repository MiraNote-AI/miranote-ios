import CoreText
import MiraNoteKit
import SwiftUI
import UIKit

/// The app's look for the Appearance setting (handoff 2026-10-24). System is
/// the original Home; Forest (screen 01) and Sunlit Pop (02) redraw Home in
/// their own colors and type. The screens the handoff draws no theme for take
/// only the background, ink, muted text and primary button colors, in
/// Josefin (Reading: around the page, never on it); the editor, its tool
/// bar, the composer and Mira chat stay on System. Values are the handoff's
/// `layout.json`.
struct Theme: Equatable {
    let appearance: AppearanceChoice

    var background: Color {
        switch appearance {
        case .system: return Palette.paper
        case .forest: return Color(hex: 0x182A24)
        case .sunlitPop: return Color(hex: 0xFFEDE5)
        }
    }

    /// Titles and primary text on `background`.
    var ink: Color {
        switch appearance {
        case .system: return Palette.ink
        case .forest: return Color(hex: 0xF6EEDC)
        case .sunlitPop: return Color(hex: 0x3E2934)
        }
    }

    /// Secondary text on `background`: System keeps the grey each screen
    /// draws; Forest takes its dateline green (8.4:1), Sunlit Pop its prompt
    /// plum (6.5:1) -- its dateline rose reads 4.4:1, under body text's 4.5.
    func muted(_ systemGrey: Color) -> Color {
        switch appearance {
        case .system: return systemGrey
        case .forest: return Color(hex: 0xB5C6B5)
        case .sunlitPop: return Color(hex: 0x694E60)
        }
    }

    /// Fill of a primary button (the Start button's color).
    var button: Color {
        switch appearance {
        case .system: return Palette.ink
        case .forest: return Color(hex: 0xD1B186)
        case .sunlitPop: return Color(hex: 0xE56E64)
        }
    }

    /// Label of a primary button: System keeps each button's own.
    func onButton(_ systemLabel: Color) -> Color {
        switch appearance {
        case .system: return systemLabel
        case .forest: return Color(hex: 0x17241D)
        case .sunlitPop: return Color(hex: 0xFFF9F3)
        }
    }

    /// Fill of a smaller primary button (a 15-17 pt label, as "+ New
    /// memory") on the theme's background: the theme's own only where its
    /// label reads at AA (4.5:1). Sunlit Pop's white on coral reads 2.98:1
    /// (its ink 4.29:1), so it keeps System's ink; the coral stays on Home's
    /// large Start label, as designed. A button on a light card keeps
    /// System's ink in every theme: a theme fill has almost no edge there.
    var smallButton: Color {
        appearance == .forest ? button : Palette.ink
    }

    /// Label of `smallButton`: System keeps each button's own.
    func onSmallButton(_ systemLabel: Color) -> Color {
        appearance == .forest ? onButton(systemLabel) : systemLabel
    }

    /// The status bar and system controls: light content on Forest.
    var colorScheme: ColorScheme {
        appearance == .forest ? .dark : .light
    }

    // MARK: Glass circles (Home's header, the back buttons)

    var circleFill: Color {
        switch appearance {
        case .system: return Color.white.opacity(0.58)
        case .forest: return Color(hex: 0x40584B).opacity(0.82)
        case .sunlitPop: return Color.white.opacity(0.86)
        }
    }

    var circleStroke: Color {
        switch appearance {
        case .system: return Color(hex: 0x48433B).opacity(0.12)
        case .forest: return Color(hex: 0xB5C6B5).opacity(0.24)
        case .sunlitPop: return Color(hex: 0xA65965).opacity(0.24)
        }
    }

    // MARK: Home

    /// Home's glyphs: the header circles' icons and the prompt spark.
    var homeIcon: Color {
        switch appearance {
        case .system: return Color(hex: 0x635B50)
        case .forest, .sunlitPop: return ink
        }
    }

    /// A Home text role: face, color and the space between its lines.
    struct HomeText {
        let font: Font
        let color: Color
        var lineSpacing: CGFloat = 0

        /// A theme face at the design's line height (a multiple of its size).
        init(_ face: UIFont, _ color: Color, lineHeight: CGFloat) {
            self.init(font: Font(face), color: color, lineSpacing: face.pointSize * lineHeight - face.lineHeight)
        }

        init(font: Font, color: Color, lineSpacing: CGFloat = 0) {
            self.font = font
            self.color = color
            self.lineSpacing = lineSpacing
        }
    }

    var wordmark: HomeText {
        switch appearance {
        case .system: return HomeText(font: .miraLogo, color: Color(hex: 0x25231F))
        case .forest: return HomeText(font: ThemeFont.dmSans(size: 17, weight: 700), color: ink)
        case .sunlitPop: return HomeText(font: ThemeFont.poppins(size: 17, weight: 600), color: ink)
        }
    }

    /// The two-line dateline, at the design's 1.18 line height on the
    /// theme faces.
    var dateline: HomeText {
        switch appearance {
        case .system: return HomeText(font: .miraDate, color: HomeView.dateColor, lineSpacing: 4)
        case .forest:
            return HomeText(ThemeFont.dmSansUIFont(size: 22, weight: 700), Color(hex: 0xB5C6B5), lineHeight: 1.18)
        case .sunlitPop:
            return HomeText(ThemeFont.poppinsUIFont(size: 22, weight: 600), Color(hex: 0xA65965), lineHeight: 1.18)
        }
    }

    /// How far the dateline's second line is indented.
    var datelineIndent: CGFloat { appearance == .system ? 80 : 52 }

    /// The two-line hero, at the design's 1.02 line height.
    var hero: HomeText {
        switch appearance {
        case .system:
            // Fraunces' own line box is ~7 pt taller than 1769_W05's.
            return HomeText(font: .miraHero, color: Color(hex: 0x24221E), lineSpacing: -7)
        case .forest:
            return HomeText(ThemeFont.playfairUIFont(size: 38), Color(hex: 0xF8ECD8), lineHeight: 1.02)
        case .sunlitPop:
            return HomeText(ThemeFont.poppinsUIFont(size: 33, weight: 600), Color(hex: 0x422C39), lineHeight: 1.02)
        }
    }

    /// Added to System's gaps above and below the hero, so its glyphs and
    /// the Start button land where the design draws them (measured against
    /// screen.png).
    var heroGaps: (above: CGFloat, below: CGFloat) {
        switch appearance {
        case .system: return (0, 0)
        case .forest: return (-1, 0)
        case .sunlitPop: return (-2, 8)
        }
    }

    var startLabelFont: Font {
        switch appearance {
        case .system: return Sans.font(size: 24.6, weight: 700)
        case .forest: return ThemeFont.dmSans(size: 23, weight: 700)
        case .sunlitPop: return ThemeFont.poppins(size: 21, weight: 600)
        }
    }

    var startLabel: Color { onButton(Color(hex: 0xFFFAF3)) }

    var promptFont: Font {
        switch appearance {
        case .system: return Sans.font(size: 16, weight: 700)
        case .forest: return ThemeFont.dmSans(size: 16, weight: 500)
        case .sunlitPop: return ThemeFont.poppins(size: 16, weight: 500)
        }
    }

    var promptFill: Color {
        switch appearance {
        case .system: return Color(hex: 0xF6F5F1)
        case .forest: return Color(hex: 0x2E4539)
        case .sunlitPop: return Color(hex: 0xFFF9F4)
        }
    }

    var promptIconFill: Color {
        switch appearance {
        case .system: return Color(hex: 0xC6B298)
        case .forest: return Color(hex: 0xD1B186)
        case .sunlitPop: return Color(hex: 0xAA77A1)
        }
    }

    var promptPlaceholder: Color {
        switch appearance {
        case .system: return Palette.ink.opacity(0.5)
        case .forest: return ink
        case .sunlitPop: return Color(hex: 0x694E60)
        }
    }

    /// The prompt field's caret.
    var promptTint: Color {
        appearance == .system ? Palette.forest : button
    }

    /// The theme's card title face; System keeps Josefin Bold 22.
    var cardTitleFace: UIFont? {
        switch appearance {
        case .system: return nil
        case .forest: return ThemeFont.dmSansUIFont(size: 22, weight: 500)
        case .sunlitPop: return ThemeFont.poppinsUIFont(size: 22, weight: 500)
        }
    }

    /// The collection cards, cycled by grid position: the design draws four
    /// per theme (left to right, top to bottom).
    func card(_ index: Int) -> HomeCollectionCard.Style {
        switch appearance {
        case .system: return HomeCollectionCard.Style.cycle(index)
        case .forest:
            // Card, art and its 70% accent layer.
            let palette: [[UInt32]] = [
                [0x4C6556, 0xC9A878, 0xE7D4AF], [0x50685E, 0xAC997F, 0xC8B18F],
                [0x365A4C, 0xB7C6B6, 0xE4EBDB], [0x6D594B, 0xD8BE9D, 0xF6E5CB]
            ]
            return Self.card(palette[index % 4], title: 0xF8ECD8, border: 0xB5C6B5)
        case .sunlitPop:
            let palette: [[UInt32]] = [
                [0xF1C6D1, 0xF7DDA8, 0xFFF2D5], [0xD8C5EA, 0xFAE2B8, 0xF8E7F6],
                [0xBBDCC8, 0xEBB3B5, 0xF7F0D8], [0xF7DFAF, 0xE7B69C, 0xFFF4DC]
            ]
            return Self.card(palette[index % 4], title: 0x422C39, border: 0xA65965)
        }
    }

    private static func card(_ colors: [UInt32], title: UInt32, border: UInt32) -> HomeCollectionCard.Style {
        HomeCollectionCard.Style(
            card: Color(hex: colors[0]), art: Color(hex: colors[1]), accent: Color(hex: colors[2]).opacity(0.7),
            title: Color(hex: title), border: Color(hex: border).opacity(0.16)
        )
    }
}

extension EnvironmentValues {
    /// Set from `AppSettings.appearance` at the app root (`HomeFlow`).
    @Entry var theme = Theme(appearance: .system)
}

/// The theme faces: DM Sans (Forest's UI, a variable font pinned at its
/// 14 pt optical size), Playfair Display Regular (Forest's hero; the default
/// instance of the variable font the Background tool already bundles) and
/// Poppins Medium / SemiBold (Sunlit Pop).
enum ThemeFont {
    private static let weightAxis = 0x77676874   // 'wght'
    private static let opticalAxis = 0x6F70737A  // 'opsz'

    static func dmSansUIFont(size: CGFloat, weight: CGFloat) -> UIFont {
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "DM Sans",
            variationKey: [weightAxis: weight, opticalAxis: 14]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func dmSans(size: CGFloat, weight: CGFloat) -> Font {
        Font(dmSansUIFont(size: size, weight: weight))
    }

    static func playfairUIFont(size: CGFloat) -> UIFont {
        UIFont(name: "PlayfairDisplay-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    static func poppinsUIFont(size: CGFloat, weight: CGFloat) -> UIFont {
        UIFont(name: weight >= 600 ? "Poppins-SemiBold" : "Poppins-Medium", size: size) ?? .systemFont(ofSize: size)
    }

    static func poppins(size: CGFloat, weight: CGFloat) -> Font {
        Font(poppinsUIFont(size: size, weight: weight))
    }
}
