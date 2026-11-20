import XCTest
@testable import MiraNoteKit

/// #206: a star's strip is the most colorful row of its page's top
/// half; a text-only page's is calm paper.
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

    /// The top half's rows on a 196 px page: 38.1 px each.
    private let row = 196.0 * 70 / 360

    /// Red and blue stripes across fold row `index`.
    private func stripes(inRow index: Int) -> (Int, Int) -> StarColor? {
        { column, line in
            guard Double(line) >= self.row * Double(index) + 2, Double(line) < self.row * Double(index + 1) - 2
            else { return nil }
            return (column / 12).isMultiple(of: 2) ? self.red : self.blue
        }
    }

    func testThePageFoldsOntoItsMostColorfulRow() {
        for index in 0..<4 {
            XCTAssertEqual(StarStrip.foldRow(in: page(stripes(inRow: index))), index, "stripes in row \(index)")
        }
        let cut = StarStrip.foldCut(2, in: page { _, _ in nil })
        XCTAssertEqual(cut.angle, 0)
        XCTAssertEqual(cut.length, 196)
        XCTAssertEqual(cut.thickness, row, accuracy: 0.001)
        XCTAssertEqual(cut.centerY, row * 2.5, accuracy: 0.001)
    }

    /// Dark text lines vary in lightness only: a small sticker's color
    /// wins over a page of words.
    func testColorBeatsGreyWords() {
        let folded = StarStrip.foldRow(in: page { column, line in
            if (125..<140).contains(line), (20..<60).contains(column) { return StarColor(240, 180, 30) }
            if (125..<140).contains(line), (60..<100).contains(column) { return StarColor(30, 150, 90) }
            return line % 10 < 3 ? StarColor(40, 40, 40) : nil
        })
        XCTAssertEqual(folded, 3, "the sticker's row")
    }

    func testAPlainPageFoldsOntoItsSecondRow() {
        XCTAssertEqual(StarStrip.foldRow(in: page { _, _ in nil }), StarStrip.plainRow)
        XCTAssertEqual(StarStrip.plainRow, 1)
    }

    func testTheStripIsTheRowsPixels() {
        let source = page(stripes(inRow: 0))
        let strip = StarStrip.strip(StarStrip.foldCut(0, in: source), from: source)
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

    // MARK: The look

    /// The star wears its strip's colors, washed toward paper and with no
    /// photo detail: the texture is blurred, the arms are its fifths.
    func testTheLookCarriesTheStripsColorsWithoutDetail() {
        var strip = StarPixels(width: 192, height: 32, fill: red)
        for column in 96..<192 {
            for row in 0..<32 { strip.set(column, row, blue) }
        }
        let look = StarStrip.look(strip)
        XCTAssertEqual(look.tints.count, 5)
        XCTAssertGreaterThan(look.tints[0].red, look.tints[0].blue, "the first arm is the strip's start")
        XCTAssertGreaterThan(look.tints[4].blue, look.tints[4].red, "the last arm its end")
        let edge = look.texture.color(95, 16), next = look.texture.color(96, 16)
        XCTAssertLessThan(abs(edge.red - next.red), (red.red - blue.red) / 2, "the cut between colors is blurred soft")
        XCTAssertGreaterThan(look.texture.color(10, 16).green, red.green, "washed toward paper")
    }

    /// A calm paper strip gives a light, warm cream star, the same on
    /// every arm.
    func testAPaperStripGivesAPaperStar() {
        let look = StarStrip.look(StarPixels(width: 192, height: 32, fill: paper))
        for tint in look.tints + [look.average] {
            XCTAssertGreaterThan(tint.luma, 220)
            XCTAssertGreaterThan(tint.red, tint.blue)
            XCTAssertEqual(tint.blue, look.tints[0].blue, accuracy: 4)
        }
    }

    /// CSS saturate: grey stays grey, 1 changes nothing, more pushes away
    /// from grey.
    func testSaturateMatchesCSS() {
        let grey = StarColor(128, 128, 128)
        XCTAssertEqual(StarStrip.saturate(grey, 1.8).red, 128, accuracy: 0.5)
        let orange = StarColor(200, 120, 60)
        XCTAssertEqual(StarStrip.saturate(orange, 1).green, 120, accuracy: 0.5)
        XCTAssertGreaterThan(StarStrip.saturate(orange, 1.8).red, orange.red)
        XCTAssertLessThan(StarStrip.saturate(orange, 1.8).blue, orange.blue)
    }
}
