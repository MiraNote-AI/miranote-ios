import XCTest
@testable import MiraNote

/// The jar's pile: every star stays inside the glass, however many, and the
/// same pages lie the same way every time.
final class StarPileTests: XCTestCase {
    private func assertInside(_ count: Int, jar: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let interior = JarGeometry(size: jar).interior
        let ids = (0..<count).map { _ in UUID() }
        let pile = StarPile.layout(ids, in: interior)
        let radius = pile.starSize / 2
        XCTAssertEqual(pile.spots.count, count, file: file, line: line)
        for spot in pile.spots {
            let point = spot.center
            XCTAssertTrue(interior.rect.insetBy(dx: radius - 0.01, dy: radius - 0.01).contains(point),
                          "\(count) stars: \(point) leaves \(interior.rect)", file: file, line: line)
            for cornerX in [interior.rect.minX + interior.corner, interior.rect.maxX - interior.corner] {
                let cornerY = interior.rect.maxY - interior.corner
                let inCorner = (cornerX < interior.midX ? point.x < cornerX : point.x > cornerX) && point.y > cornerY
                guard inCorner else { continue }
                let distance = hypot(point.x - cornerX, point.y - cornerY)
                XCTAssertLessThanOrEqual(
                    distance, interior.corner - radius + 0.01,
                    "\(count) stars: \(point) pokes through a bottom corner", file: file, line: line
                )
            }
        }
    }

    func testStarsStayInsideTheJarOnLargeAndSmallPhones() {
        for count in 0...120 {
            assertInside(count, jar: CGSize(width: 320, height: 400))
            assertInside(count, jar: CGSize(width: 240, height: 300))
        }
    }

    func testAFewStarsAreAsLargeAsAllowed() {
        for jar in [CGSize(width: 320, height: 400), CGSize(width: 240, height: 300)] {
            let interior = JarGeometry(size: jar).interior
            for count in [1, 3, 5] {
                XCTAssertEqual(StarPile.layout((0..<count).map { _ in UUID() }, in: interior).starSize,
                               StarPile.largest, "\(count) stars in \(jar)")
            }
        }
    }

    /// iPhone 17 Pro's jar (interior 313 x 310 pt): 8 stars at the cap, 30 at 42.
    func testTheSizeShrinksAsTheJarFills() {
        let interior = JarGeometry(size: CGSize(width: 320, height: 400)).interior
        XCTAssertEqual(StarPile.starSize(8, in: interior), 64)
        XCTAssertEqual(StarPile.starSize(30, in: interior), 42)
        var previous = StarPile.largest
        for count in 1...120 {
            let size = StarPile.starSize(count, in: interior)
            XCTAssertLessThanOrEqual(size, previous, "\(count) stars grow the stars")
            previous = size
        }
        XCTAssertLessThan(StarPile.starSize(90, in: interior), StarPile.starSize(5, in: interior))
    }

    func testThePileFillsAtMostTwoThirdsOfTheJar() {
        for jar in [CGSize(width: 320, height: 400), CGSize(width: 240, height: 300)] {
            let interior = JarGeometry(size: jar).interior
            for count in 1...120 {
                let size = StarPile.starSize(count, in: interior)
                // Past the crowd floor a full jar may fill more, to fit at all.
                guard size > StarPile.crowdLargest else { continue }
                XCTAssertLessThanOrEqual(StarPile.pileHeight(count, size: size, width: interior.width),
                                         interior.rect.height * StarPile.fillShare, "\(count) stars in \(jar)")
            }
        }
    }

    func testACrowdStillFits() {
        let interior = JarGeometry(size: CGSize(width: 240, height: 300)).interior
        for count in [90, 120] {
            let size = StarPile.starSize(count, in: interior)
            XCTAssertLessThanOrEqual(StarPile.pileHeight(count, size: size, width: interior.width),
                                     interior.rect.height * 0.9, "\(count) stars overfill the jar")
        }
    }

    func testTheSamePagesLieTheSameWay() {
        let interior = JarGeometry(size: CGSize(width: 320, height: 400)).interior
        let ids = (0..<20).map { _ in UUID() }
        let first = StarPile.layout(ids, in: interior).spots
        let again = StarPile.layout(ids, in: interior).spots
        XCTAssertEqual(first.map(\.center), again.map(\.center))
        XCTAssertEqual(first.map(\.rotation), again.map(\.rotation))
    }
}
