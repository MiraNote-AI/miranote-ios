import UIKit
import XCTest
@testable import MiraNote

final class DetailFontTests: XCTestCase {
    func testDefaultIsKaiti() {
        XCTAssertEqual(DetailFont.standard, .kaiti)
        XCTAssertEqual(DetailFont.kaiti.postScriptName, "STKaitiSC-Regular")
        XCTAssertEqual(DetailFont.songti.postScriptName, "STSongti-SC-Regular")
    }

    func testUnavailableNameFallsBackToSystemFont() {
        let font = DetailFont.uiFont(named: "Not-A-Real-Font-Regular", size: 22)
        XCTAssertEqual(font.pointSize, 22, accuracy: 0.001)
        XCTAssertEqual(font.fontName, UIFont.systemFont(ofSize: 22).fontName)
    }

    func testCanvasResolvesUnknownFontNameToSystemFont() {
        let font = TextFace.uiFont(name: "STKaitiSC-Not-Downloaded", size: 22)
        XCTAssertEqual(font.fontName, UIFont.systemFont(ofSize: 22).fontName)
        XCTAssertEqual(font.pointSize, 22, accuracy: 0.001)
    }

    func testInstalledNameIsUsed() {
        // Helvetica ships with iOS: a PostScript name resolves to itself.
        XCTAssertEqual(DetailFont.uiFont(named: "Helvetica", size: 18).fontName, "Helvetica")
    }
}
