import XCTest
@testable import MiraNoteKit

/// #206: a star's strip is the most colorful band of its page at 30
/// degrees; a text-only page's is calm paper.
final class StarStripTests: XCTestCase {
    private let paper = StarColor(244, 238, 226)
    private let red = StarColor(220, 40, 50)
    private let blue = StarColor(40, 80, 220)

    /// A 196 x 256 page of paper, with `paint` deciding pixels over it.
    private func page(_ paint: (Int, Int) -> StarColor?) -> StarPixels {
        var page = StarPixels(width: 196, height: 256, fill: paper)
        for row in 0..<256 {
            for column in 0..<196 {
                if let color = paint(column, row) { page.set(column, row, color) }
            }
        }
        return page
    }

    /// Red and blue stripes inside the band through (98, `middle`) at
    /// `angle`.
    private func band(middle: Double, angle: Double) -> (Int, Int) -> StarColor? {
        { column, row in
            let dx = Double(column) - 98, dy = Double(row) - middle
            let across = -dx * sin(angle) + dy * cos(angle)
            let along = dx * cos(angle) + dy * sin(angle)
            guard abs(across) < 14 else { return nil }
            return Int((along + 200) / 12).isMultiple(of: 2) ? self.red : self.blue
        }
    }

    func testTheCutFollowsTheColorfulBandDownToTheRight() {
        let cut = StarStrip.colorfulCut(in: page(band(middle: 180, angle: .pi / 6)))
        XCTAssertEqual(cut.angle, .pi / 6, accuracy: 0.001)
        XCTAssertEqual(cut.centerY, 180, accuracy: 4)
        XCTAssertEqual(cut.length, 196)
        XCTAssertEqual(cut.thickness, 196 / 6, accuracy: 0.001)
    }

    func testTheCutFollowsTheColorfulBandUpToTheRight() {
        let cut = StarStrip.colorfulCut(in: page(band(middle: 100, angle: -.pi / 6)))
        XCTAssertEqual(cut.angle, -.pi / 6, accuracy: 0.001)
        XCTAssertEqual(cut.centerY, 100, accuracy: 4)
    }

    /// Dark text lines vary in lightness only: a small sticker's color
    /// wins over a page of words.
    func testColorBeatsGreyWords() {
        let cut = StarStrip.colorfulCut(in: page { column, row in
            if (150..<175).contains(row), (20..<60).contains(column) { return StarColor(240, 180, 30) }
            if (150..<175).contains(row), (60..<100).contains(column) { return StarColor(30, 150, 90) }
            return row % 10 < 3 ? StarColor(40, 40, 40) : nil
        })
        // The band's middle line passes over the sticker.
        let atSticker = cut.centerY + (40 - cut.centerX) * tan(cut.angle)
        XCTAssertTrue((140..<185).contains(atSticker), "band at x=40 is y=\(atSticker)")
    }

    func testTheStripIsTheBandsPixels() {
        let source = page(band(middle: 128, angle: .pi / 6))
        let strip = StarStrip.strip(StarStrip.colorfulCut(in: source), from: source)
        XCTAssertEqual(strip.width, 192)
        XCTAssertEqual(strip.height, 32)
        let middle = (0..<192).map { strip.color($0, 16) }
        XCTAssertTrue(middle.contains { $0.red > 180 && $0.blue < 90 }, "red stripes")
        XCTAssertTrue(middle.contains { $0.blue > 180 && $0.red < 90 }, "blue stripes")
    }

    // MARK: Calm paper stars

    private var textStrip: StarPixels {
        var strip = StarPixels(width: 192, height: 32, fill: paper)
        for column in 40..<120 {
            for row in 12..<18 { strip.set(column, row, StarColor(30, 30, 160)) }
        }
        return strip
    }

    func testACalmStarIsItsPaperWithFaintGraphiteWords() {
        let calm = StarStrip.calm(textStrip, id: UUID())
        let ground = calm.color(5, 5)
        let light = ground.red / paper.red
        XCTAssertEqual(ground.green / paper.green, light, accuracy: 0.01, "the paper's own color")
        XCTAssertEqual(ground.blue / paper.blue, light, accuracy: 0.01, "the paper's own color")

        let word = calm.color(60, 15)
        XCTAssertLessThan(word.red, ground.red, "the words still show")
        XCTAssertGreaterThan(word.red, 150, "faintly: not boosted to ink")
        XCTAssertLessThan(abs(word.blue - word.red), 25, "in graphite, not the ink's blue")
    }

    func testCalmPaperVariesByAtMostThreePercentByPage() {
        let lights = (0..<200).map { _ in StarStrip.calm(textStrip, id: UUID()).color(5, 5).green / paper.green }
        XCTAssertGreaterThanOrEqual(lights.min() ?? 0, 0.97 - 0.005)
        XCTAssertLessThanOrEqual(lights.max() ?? 2, 1.03 + 0.005)
        XCTAssertGreaterThan((lights.max() ?? 0) - (lights.min() ?? 0), 0.03, "pages do differ")
        let id = UUID()
        XCTAssertEqual(StarStrip.calm(textStrip, id: id), StarStrip.calm(textStrip, id: id), "the same every time")
    }

    // MARK: The wrap

    /// The strip's start winds clockwise from the top tip: its first half
    /// is the star's right side, its second half the left.
    func testTheStripWindsClockwiseFromTheTopTip() {
        var strip = StarPixels(width: 192, height: 32, fill: red)
        for column in 96..<192 {
            for row in 0..<32 { strip.set(column, row, blue) }
        }
        let face = StarStrip.wrap(strip, side: 96)
        XCTAssertEqual(face.width, 96)
        let right = face.color(70, 52), left = face.color(25, 52)
        XCTAssertGreaterThan(right.red, right.blue, "right side: the strip's first half")
        XCTAssertGreaterThan(left.blue, left.red, "left side: the strip's second half")
    }
}
