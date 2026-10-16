import SwiftUI
import UIKit
import XCTest
@testable import MiraNote

/// Home collection card titles (Bold 20: WCAG large text) read at 3:1 or
/// better on every card of the cycle (AA for large text): the handoff's
/// #D9CDBA titles were 1.5:1 on the tan card ("Little Joys" on a fresh
/// install) and about 2.4:1 on two others. The cards themselves stay as
/// close to the design as that allows.
final class HomeCardContrastTests: XCTestCase {
    /// Red, green, blue.
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

    func testEveryCardTitleReadsAtAAForLargeText() {
        for index in 0..<4 {
            let style = HomeCollectionCard.Style.cycle(index)
            XCTAssertGreaterThanOrEqual(contrast(style.title, style.card), 3, "card \(index)")
        }
    }

    /// Paper titles reach 3:1 on the drawn grey and olive cards, so those
    /// keep the design's colors; the tan card keeps its ink title.
    func testTheGreyAndOliveCardsKeepTheDesignColors() {
        XCTAssertEqual(hex(HomeCollectionCard.Style.cycle(0).card), 0x8F7E76, "grey")
        XCTAssertEqual(hex(HomeCollectionCard.Style.cycle(2).card), 0x878476, "olive")
        XCTAssertEqual(hex(HomeCollectionCard.Style.cycle(3).title), hex(Palette.ink), "tan keeps its ink title")
    }
}
