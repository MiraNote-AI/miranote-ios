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
                XCTAssertLessThanOrEqual(distance, interior.corner - radius + 0.01,
                                         "\(count) stars: \(point) pokes through a bottom corner", file: file, line: line)
            }
        }
    }

    func testStarsStayInsideTheJarOnLargeAndSmallPhones() {
        for count in [0, 1, 5, 12, 30, 60, 90] {
            assertInside(count, jar: CGSize(width: 320, height: 400))
            assertInside(count, jar: CGSize(width: 240, height: 300))
        }
    }

    func testACrowdShrinksTheStars() {
        let interior = JarGeometry(size: CGSize(width: 240, height: 300)).interior
        let few = StarPile.layout((0..<5).map { _ in UUID() }, in: interior)
        let crowd = StarPile.layout((0..<90).map { _ in UUID() }, in: interior)
        XCTAssertEqual(few.starSize, StarPile.largest)
        XCTAssertLessThan(crowd.starSize, few.starSize)
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
