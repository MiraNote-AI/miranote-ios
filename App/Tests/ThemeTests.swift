import MiraNoteKit
import SwiftUI
import UIKit
import XCTest
@testable import MiraNote

/// The Appearance setting picks the theme (handoff 2026-10-24, screens
/// 01-02), and every theme's text reads on its background.
final class ThemeTests: XCTestCase {
    private func components(_ color: Color) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue]
    }

    private func luminance(_ color: Color) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return zip([0.2126, 0.7152, 0.0722], components(color)).reduce(0) { $0 + $1.0 * linear($1.1) }
    }

    private func contrast(_ lhs: Color, _ rhs: Color) -> CGFloat {
        let (high, low) = (max(luminance(lhs), luminance(rhs)), min(luminance(lhs), luminance(rhs)))
        return (high + 0.05) / (low + 0.05)
    }

    private func hex(_ color: Color) -> Int {
        components(color).reduce(0) { $0 << 8 | Int(($1 * 255).rounded()) }
    }

    func testTheStoredAppearanceSelectsTheTheme() throws {
        let suite = "ThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(hex(Theme(appearance: AppSettings(defaults: defaults).appearance).background), 0xF6F4E8,
                       "nothing stored: System")
        AppSettings(defaults: defaults).appearance = .forest
        XCTAssertEqual(hex(Theme(appearance: AppSettings(defaults: defaults).appearance).background), 0x182A24)
        AppSettings(defaults: defaults).appearance = .sunlitPop
        XCTAssertEqual(hex(Theme(appearance: AppSettings(defaults: defaults).appearance).background), 0xFFEDE5)
    }

    /// Ink, button and button label of each theme.
    func testEachThemeTakesTheDesignColors() {
        let expected: [AppearanceChoice: [Int]] = [
            .system: [0x201E1C, 0x201E1C, 0xFFFAF3],
            .forest: [0xF6EEDC, 0xD1B186, 0x17241D],
            .sunlitPop: [0x3E2934, 0xE56E64, 0xFFF9F3]
        ]
        for (choice, colors) in expected {
            let theme = Theme(appearance: choice)
            XCTAssertEqual([hex(theme.ink), hex(theme.button), hex(theme.startLabel)], colors, "\(choice)")
        }
    }

    /// Light status bar content on Forest only.
    func testOnlyForestIsDark() {
        XCTAssertEqual(Theme(appearance: .system).colorScheme, .light)
        XCTAssertEqual(Theme(appearance: .forest).colorScheme, .dark)
        XCTAssertEqual(Theme(appearance: .sunlitPop).colorScheme, .light)
    }

    /// System keeps each screen's own grey; the themes replace it.
    func testMutedTextFollowsTheTheme() {
        XCTAssertEqual(hex(Theme(appearance: .system).muted(Palette.textSecondary)), hex(Palette.textSecondary))
        XCTAssertEqual(hex(Theme(appearance: .forest).muted(Palette.textSecondary)), 0xB5C6B5)
        XCTAssertEqual(hex(Theme(appearance: .sunlitPop).muted(Palette.textSecondary)), 0x694E60)
    }

    /// Body text (AA, 4.5:1) on Forest and Sunlit Pop backgrounds: titles,
    /// the muted lines and the prompt bar's words.
    func testThemeTextReadsAtAAOnItsBackground() {
        for choice in [AppearanceChoice.forest, .sunlitPop] {
            let theme = Theme(appearance: choice)
            XCTAssertGreaterThanOrEqual(contrast(theme.ink, theme.background), 4.5, "\(choice) ink")
            XCTAssertGreaterThanOrEqual(contrast(theme.muted(.clear), theme.background), 4.5, "\(choice) muted")
            XCTAssertGreaterThanOrEqual(contrast(theme.ink, theme.promptFill), 4.5, "\(choice) prompt")
        }
    }

    /// Card titles (Medium 22: large text) read at 3:1 on every card.
    func testThemeCardTitlesReadOnEveryCard() {
        for choice in [AppearanceChoice.forest, .sunlitPop] {
            for index in 0..<4 {
                let style = Theme(appearance: choice).card(index)
                XCTAssertGreaterThanOrEqual(contrast(style.title, style.card), 3, "\(choice) card \(index)")
            }
        }
    }

    func testSystemHomeKeepsTheOriginalCards() {
        for index in 0..<4 {
            let theme = Theme(appearance: .system).card(index)
            let original = HomeCollectionCard.Style.cycle(index)
            XCTAssertEqual(hex(theme.card), hex(original.card))
            XCTAssertEqual(hex(theme.title), hex(original.title))
        }
        XCTAssertNil(Theme(appearance: .system).cardTitleFace, "System keeps Josefin")
    }

    /// The bundled theme faces are registered (UIAppFonts).
    func testThemeFacesAreBundled() {
        XCTAssertEqual(ThemeFont.playfairUIFont(size: 38).familyName, "Playfair Display")
        XCTAssertEqual(ThemeFont.poppinsUIFont(size: 33, weight: 600).fontName, "Poppins-SemiBold")
        XCTAssertEqual(ThemeFont.poppinsUIFont(size: 16, weight: 500).fontName, "Poppins-Medium")
        XCTAssertEqual(ThemeFont.dmSansUIFont(size: 16, weight: 500).familyName, "DM Sans")
    }

    /// DM Sans is one variable font: the weight asked for is the instance
    /// drawn (not the file's default 400).
    func testDMSansResolvesTheWeightAskedFor() {
        for weight in [500, 700] as [CGFloat] {
            let font = ThemeFont.dmSansUIFont(size: 16, weight: weight) as CTFont
            let variation = CTFontCopyVariation(font) as? [Int: CGFloat] ?? [:]
            XCTAssertEqual(variation[0x77676874], weight, "wght of \(weight)")
        }
    }

    /// Smaller primary buttons ("+ New memory") read at AA (4.5:1) and stand
    /// out from the theme's background (3:1) in every theme.
    func testSmallButtonsReadAtAA() {
        for choice in AppearanceChoice.allCases {
            let theme = Theme(appearance: choice)
            let label = theme.onSmallButton(Palette.onInk)
            XCTAssertGreaterThanOrEqual(contrast(label, theme.smallButton), 4.5, "\(choice)")
            XCTAssertGreaterThanOrEqual(contrast(theme.smallButton, theme.background), 3, "\(choice) edge")
        }
    }

    /// A wrapped Chinese title gets no stray space where its lines rejoin;
    /// Latin words, and Latin next to Chinese, keep theirs.
    func testCardTitleLinesRejoinWithoutSpacesBetweenCJK() {
        let travel = "\u{65C5}\u{884C}", notes = "\u{624B}\u{8D26}"  // two-character Chinese words
        XCTAssertEqual(ThemedCardTitle.joined([travel, notes]), travel + notes)
        XCTAssertEqual(ThemedCardTitle.joined(["Travel", "Scrapbook"]), "Travel Scrapbook")
        XCTAssertEqual(ThemedCardTitle.joined(["Tokyo", travel]), "Tokyo " + travel)
    }
}
