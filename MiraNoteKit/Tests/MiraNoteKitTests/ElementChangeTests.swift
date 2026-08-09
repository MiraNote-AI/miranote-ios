import XCTest
@testable import MiraNoteKit

// The helper mirrors ElementChange's wire-contract field names.
// swiftlint:disable identifier_name

final class ElementChangeTests: XCTestCase {
    /// Never 360: a hardcoded design width must fail these.
    private let width: CGFloat = 393
    private let id = UUID()
    private var handles: [String: CanvasItem.ID] { ["t1": id] }

    private func change(
        _ handle: String = "t1", x: Double? = nil, y: Double? = nil,
        w: Double? = nil, h: Double? = nil, pointSize: Double? = nil,
        color: String? = nil, layer: ElementChange.Layer? = nil
    ) -> ElementChange {
        ElementChange(handle: handle, x: x, y: y, w: w, h: h,
                      pointSize: pointSize, color: color, layer: layer)
    }

    private func resolve(_ changes: [ElementChange]) -> [ResolvedChange] {
        PageEditGuard.resolve(changes, handles: handles, canvasWidth: width)
    }

    // MARK: Resolving

    func testKnownHandleResolvesToItsItemID() {
        let resolved = resolve([change(x: 40)])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].id, id)
        XCTAssertEqual(resolved[0].x, 40)
    }

    func testInventedHandleIsDropped() {
        XCTAssertTrue(resolve([change("t9", x: 40)]).isEmpty)
    }

    func testUnknownColorIsDroppedButTheRestOfTheEntrySurvives() {
        let resolved = resolve([change(x: 40, color: "warm beige")])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertNil(resolved[0].colorName)
        XCTAssertEqual(resolved[0].x, 40)
    }

    func testKnownColorSurvives() {
        XCTAssertEqual(resolve([change(color: "forest")])[0].colorName, "forest")
    }

    // MARK: Clamping

    func testAnXInsideTheRealCanvasIsLeftAlone() {
        // 380 fits a 393 canvas and would be clamped by a hardcoded 360.
        XCTAssertEqual(resolve([change(x: 380)])[0].x, 380)
    }

    func testXBeyondTheCanvasIsPulledBackIn() {
        XCTAssertEqual(resolve([change(x: 900)])[0].x, 393)
    }

    func testNegativeXIsPulledToTheEdge() {
        XCTAssertEqual(resolve([change(x: -20)])[0].x, 0)
    }

    func testNegativeYIsClampedButLargeYIsAllowed() {
        // The canvas scrolls downward without limit; only the top is a wall.
        XCTAssertEqual(resolve([change(y: -50)])[0].y, 0)
        XCTAssertEqual(resolve([change(y: 5000)])[0].y, 5000)
    }

    func testPointSizeClampsTo11Through48() {
        XCTAssertEqual(resolve([change(pointSize: 4)])[0].pointSize, 11)
        XCTAssertEqual(resolve([change(pointSize: 900)])[0].pointSize, 48)
        XCTAssertEqual(resolve([change(pointSize: 34)])[0].pointSize, 34)
    }

    // MARK: Merging

    func testMergeLetsLaterCallsWinFieldByField() {
        let merged = PageEditGuard.merge([
            [change(x: 10, y: 10)],
            [change(x: 99)]
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].x, 99)
        XCTAssertEqual(merged[0].y, 10, "an untouched field must survive the merge")
    }

    func testMergeKeepsDistinctHandlesSeparate() {
        XCTAssertEqual(PageEditGuard.merge([[change("t1", x: 1)], [change("p1", x: 2)]]).count, 2)
    }

    func testMergePreservesFirstAppearanceOrder() {
        let merged = PageEditGuard.merge([
            [change("p1", x: 1), change("t1", x: 2)],
            [change("t1", x: 3)]
        ])
        XCTAssertEqual(merged.map(\.handle), ["p1", "t1"])
    }

    func testMergeOfNothingIsNothing() {
        XCTAssertTrue(PageEditGuard.merge([]).isEmpty)
        XCTAssertTrue(PageEditGuard.merge([[]]).isEmpty)
    }

    // MARK: Wire shape

    func testDecodesTheKeysTheBackendSends() throws {
        let json = Data("""
        {"id":"t1","x":28,"y":24,"size":34,"color":"forest","layer":"front"}
        """.utf8)
        let change = try JSONDecoder().decode(ElementChange.self, from: json)
        XCTAssertEqual(change.handle, "t1")
        XCTAssertEqual(change.pointSize, 34)
        XCTAssertEqual(change.layer, .front)
    }

    func testDecodesAnEntryThatOnlyNamesAnElement() throws {
        let change = try JSONDecoder().decode(
            ElementChange.self, from: Data(#"{"id":"p1"}"#.utf8)
        )
        XCTAssertEqual(change.handle, "p1")
        XCTAssertNil(change.x)
        XCTAssertNil(change.layer)
    }
}

// swiftlint:enable identifier_name
