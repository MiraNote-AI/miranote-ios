import SwiftUI
import UIKit
import XCTest
@testable import MiraNote

/// Saved words keep the colors they were written in: a redesign of the UI
/// tokens must not repaint existing pages.
final class PaletteTests: XCTestCase {
    private func hex(_ color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    func testSavedNamesKeepTheirPreRedesignColors() {
        XCTAssertEqual(hex(Palette.color(named: "ink")), 0x201C16)
        XCTAssertEqual(hex(Palette.color(named: "onInk")), 0xF6F2EA)
        XCTAssertEqual(hex(Palette.color(named: "forest")), 0x353F2D)
        XCTAssertEqual(hex(Palette.color(named: "textSecondary")), 0x8B857A)
    }

    func testCustomAndUnknownNames() {
        XCTAssertEqual(hex(Palette.color(named: "#24382D")), 0x24382D)
        XCTAssertEqual(hex(Palette.color(named: "no such color")), 0x201C16, "unknown reads as ink")
    }
}
