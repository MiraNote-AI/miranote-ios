import SwiftUI
import XCTest
@testable import MiraNote

/// The settled card and the ending's words must share the screen: on an SE
/// (375 x 667) an eight-photo ending used to need 733 pt, clipping Keep.
final class TriggerStageTests: XCTestCase {
    /// The words and button of an eight-photo ending with 22-character
    /// lines, as measured on screen.
    private let words: CGFloat = 190

    private func bottom(of stage: TriggerStage) -> CGFloat {
        stage.card(settled: true).maxY
            + TriggerEndingText.room(content: words, bottomInset: stage.insets.bottom)
    }

    func testAShortScreenShrinksTheCardToFitTheWords() {
        let insets = EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
        let natural = TriggerStage(size: CGSize(width: 375, height: 667), insets: insets, count: 8, reduceMotion: false)
        XCTAssertGreaterThan(bottom(of: natural), 667, "unmeasured, the card keeps its size")
        var fitted = natural
        fitted.endingContent = words
        XCTAssertLessThanOrEqual(bottom(of: fitted), 667)
    }

    func testATallScreenKeepsItsCard() {
        let insets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        let natural = TriggerStage(size: CGSize(width: 402, height: 874), insets: insets, count: 8, reduceMotion: false)
        var fitted = natural
        fitted.endingContent = words
        XCTAssertEqual(fitted.card(settled: true), natural.card(settled: true))
    }
}
