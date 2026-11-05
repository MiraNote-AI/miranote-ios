import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

final class DetailFontTests: XCTestCase {
    func testDefaultIsKaiti() {
        XCTAssertEqual(DetailFont.standard, .kaiti)
        XCTAssertEqual(DetailFont.kaiti.postScriptName, "STKaitiSC-Regular")
        XCTAssertEqual(DetailFont.songti.postScriptName, "STSongti-SC-Regular")
    }

    func testQuestionIsWeibeiFallingBackToSystemFontAtItsSize() {
        XCTAssertEqual(QuestionFont.postScriptName, "WeibeiSC-Bold")
        let font = QuestionFont.uiFont(size: 22)
        XCTAssertEqual(font.pointSize, 22, accuracy: 0.001)
        XCTAssertTrue([QuestionFont.postScriptName, UIFont.systemFont(ofSize: 22).fontName].contains(font.fontName))
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

    /// G6: a detail block sized while the face was still downloading (the
    /// system font shows then) must still hold the lines once the face has
    /// landed -- the canvas only grows a block on open, never shrinks it.
    /// Measured with the system font alone the face needs 5 pt more.
    func testBlockSizedBeforeTheDownloadHoldsTheFace() throws {
        let width = MiraNoteConfig.pageWidth - 2 * TriggerDraftBuilder.margin
        let samples = [
            "\u{684C}\u{4E0A}\u{6709}\u{4E00}\u{675F}\u{5B89}\u{9759}\u{7684}\u{5149}\u{FF0C}"
                + "\u{6162}\u{6162}\u{843D}\u{5728}\u{676F}\u{5B50}\u{8FB9}\u{4E0A}\u{3002}",
            String(repeating: "\u{98CE}\u{5F88}\u{5927}\u{FF0C}\u{6211}\u{4EEC}\u{8D70}\u{5F97}\u{5F88}"
                + "\u{6162}\u{3002}", count: 4),
            "\u{4E0B}\u{5348}3\u{70B9}\u{5728} Riverside Park \u{6563}\u{6B65}\u{FF0C}"
                + "\u{98CE}\u{5F88}\u{5927}\u{3002}",
            "A quiet light on the table, slowly settling by the cup."
        ]
        var checked = 0
        for face in DetailFont.allCases {
            let name = face.postScriptName
            guard let real = UIFont(name: name, size: 22) else { continue }
            let pending = try XCTUnwrap(
                DetailFont.pendingMeasureFonts(named: name, size: 22, available: { _ in false }))
            for text in samples {
                let stand = TextMeasure.blockHeight(text: text, fonts: pending, width: width)
                let landed = TextMeasure.blockHeight(text: text, fonts: [real], width: width)
                let system = TextMeasure.blockHeight(text: text, fonts: [.systemFont(ofSize: 22)], width: width)
                print("G6 \(face) system=\(system) pending=\(stand) face=\(landed) text=\(text.prefix(12))")
                XCTAssertLessThanOrEqual(landed, stand + 0.5, "\(face): \(text)")
                checked += 1
            }
        }
        if checked == 0 { throw XCTSkip("neither face has downloaded on this device") }
    }

    func testOnlyAPendingDetailFaceIsMeasuredWithTheStandIn() {
        XCTAssertNil(DetailFont.pendingMeasureFonts(named: "Futura", size: 22, available: { _ in false }))
        XCTAssertNil(DetailFont.pendingMeasureFonts(named: DetailFont.kaiti.postScriptName, size: 22,
                                                    available: { _ in true }))
        let fonts = DetailFont.pendingMeasureFonts(named: DetailFont.songti.postScriptName, size: 22,
                                                   available: { _ in false })
        XCTAssertEqual(fonts?.map(\.fontName),
                       [UIFont.systemFont(ofSize: 22).fontName, DetailFont.metricsStandIn])
    }
}
