import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// Settings > Text size scales the app's own type; a page's words keep the
/// sizes they were written at. Restores the simulator's setting.
final class TextScaleTests: XCTestCase {
    private let key = "miranote.settings.textScale"
    private var stored: Any?
    private var before: Double = 1

    override func setUp() {
        stored = UserDefaults.standard.object(forKey: key)
        before = AppSettings.shared.textScale
    }

    override func tearDown() {
        AppSettings.shared.setTextScale(before)
        UserDefaults.standard.set(stored, forKey: key)
    }

    func testChromeFontsFollowTheScale() {
        AppSettings.shared.setTextScale(1)
        XCTAssertEqual(Sans.uiFont(size: 16, weight: 600).pointSize, 16, "100% is the size asked for")

        AppSettings.shared.setTextScale(1.25)
        XCTAssertEqual(TextScale.current, 1.25)
        XCTAssertEqual(TextScale.scaled(16), 20)
        XCTAssertEqual(Sans.uiFont(size: 16, weight: 600).pointSize, 20, accuracy: 0.001)
        XCTAssertEqual(Serif.uiFont(size: 39, weight: 410, optical: 144).pointSize, 48.75, accuracy: 0.001)
        XCTAssertEqual(ThemeFont.dmSansUIFont(size: 22, weight: 700).pointSize, 27.5, accuracy: 0.001)
        XCTAssertEqual(ThemeFont.poppinsUIFont(size: 20, weight: 600).pointSize, 25, accuracy: 0.001)
        XCTAssertEqual(ThemeFont.playfairUIFont(size: 40).pointSize, 50, accuracy: 0.001)

        AppSettings.shared.setTextScale(0.8)
        XCTAssertEqual(Sans.uiFont(size: 15, weight: 500).pointSize, 12, accuracy: 0.001)
    }

    func testTheScaleStaysInItsRange() {
        AppSettings.shared.setTextScale(2)
        XCTAssertEqual(TextScale.current, 1.25)
        AppSettings.shared.setTextScale(0.1)
        XCTAssertEqual(TextScale.current, 0.8)
        AppSettings.shared.setTextScale(.nan)
        XCTAssertEqual(TextScale.current, 1)
    }

    /// Text blocks (every face, the classic serif display cut too), the
    /// reading view's fallback title and the page markers ask unscaled.
    func testPageContentIgnoresTheScale() {
        AppSettings.shared.setTextScale(1.25)
        for face in TextFace.choices {
            XCTAssertEqual(TextFace.uiFont(name: face.name, size: 21).pointSize, 21, accuracy: 0.001, face.label)
            XCTAssertEqual(TextFace.uiFont(name: face.name, size: 48).pointSize, 48, accuracy: 0.001, face.label)
        }
        XCTAssertEqual(Sans.uiFont(size: 13, weight: 500, scaled: false).pointSize, 13)
        XCTAssertEqual(Serif.uiFont(size: 30, weight: 560, optical: 72, scaled: false).pointSize, 30, accuracy: 0.001)
    }
}
