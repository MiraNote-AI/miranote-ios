import SwiftUI
import UIKit
import XCTest
@testable import MiraNote

/// Home collection card titles read at 4.5:1 or better on every card of
/// the cycle (WCAG AA): the handoff's #D9CDBA titles were 1.5:1 on the tan
/// card ("Little Joys" on a fresh install) and about 2.4:1 on two others.
final class HomeCardContrastTests: XCTestCase {
    private func luminance(_ color: Color) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func contrast(_ lhs: Color, _ rhs: Color) -> CGFloat {
        let (high, low) = (max(luminance(lhs), luminance(rhs)), min(luminance(lhs), luminance(rhs)))
        return (high + 0.05) / (low + 0.05)
    }

    func testEveryCardTitleReadsAtAA() {
        for index in 0..<4 {
            let style = HomeCollectionCard.Style.cycle(index)
            XCTAssertGreaterThanOrEqual(contrast(style.title, style.card), 4.5, "card \(index)")
        }
    }
}
