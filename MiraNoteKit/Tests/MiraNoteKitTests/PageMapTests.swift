import XCTest
@testable import MiraNoteKit

final class PageMapTests: XCTestCase {
    /// Deliberately not 360: a hardcoded design width must fail here.
    private let width: CGFloat = 393

    private func text(_ body: String, y: CGFloat, size: CGFloat = 17) -> CanvasItem {
        CanvasItem(
            content: .text(TextBlock(text: body, pointSize: size)),
            position: CGPoint(x: 180, y: y),
            size: CGSize(width: 304, height: 44)
        )
    }

    func testMapReportsTheRealCanvasWidth() {
        let memory = Memory(items: [text("hello", y: 60)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertEqual(map.width, 393)
    }

    func testElementsAreOrderedTopToBottomNotByCreation() {
        let memory = Memory(items: [text("lower", y: 400), text("upper", y: 60)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertEqual(map.elements.map(\.says), ["upper", "lower"])
        XCTAssertEqual(map.elements.map(\.handle), ["t1", "t2"])
    }

    func testHandlesAreNumberedPerKind() {
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: "f", summary: "a bowl")),
            position: CGPoint(x: 180, y: 200),
            size: CGSize(width: 280, height: 200)
        )
        let memory = Memory(items: [text("title", y: 60), photo, text("body", y: 500)])
        let (map, handles) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertEqual(map.elements.map(\.handle), ["t1", "p1", "t2"])
        XCTAssertEqual(handles.count, 3)
        XCTAssertEqual(handles["p1"], photo.id)
    }

    func testBoxesAreTopLeftNotCentered() {
        // position is the CENTER; the map must emit the corner.
        let memory = Memory(items: [text("hello", y: 100)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        let element = map.elements[0]
        XCTAssertEqual(element.x, 180 - 304 / 2)
        XCTAssertEqual(element.y, 100 - 44 / 2)
        XCTAssertEqual(element.w, 304)
        XCTAssertEqual(element.h, 44)
    }

    func testDefaultStyleIsOmitted() {
        let memory = Memory(items: [text("hello", y: 60)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertNil(map.elements[0].color)
        XCTAssertNil(map.elements[0].rotation)
        XCTAssertNil(map.elements[0].treatment)
        XCTAssertEqual(map.elements[0].pointSize, 17)
    }

    func testNonDefaultStyleIsCarried() {
        var item = text("hello", y: 60)
        item.rotation = 8
        item.content = .text(TextBlock(text: "hello", pointSize: 30, colorName: "forest"))
        let (map, _) = PageMap.build(from: Memory(items: [item]), canvasWidth: width)
        XCTAssertEqual(map.elements[0].color, "forest")
        XCTAssertEqual(map.elements[0].rotation, 8)
    }

    func testPhotoWithoutVisionSaysSo() {
        let photo = CanvasItem(
            content: .image(ImageRef(displayName: "d", fileName: "f", summary: "")),
            position: CGPoint(x: 180, y: 200)
        )
        let (map, _) = PageMap.build(from: Memory(items: [photo]), canvasWidth: width)
        XCTAssertTrue(map.elements[0].says.contains("has not looked at"))
    }

    func testCapAt24AndStateTheRemainder() {
        let items = (0..<30).map { text("block \($0)", y: CGFloat($0) * 50) }
        let (map, handles) = PageMap.build(from: Memory(items: items), canvasWidth: width)
        XCTAssertEqual(map.elements.count, PageMap.maxElements)
        XCTAssertEqual(map.omitted, 6)
        XCTAssertEqual(handles.count, PageMap.maxElements)
    }

    func testPaletteIsStatedSoTheModelNeedNotGuess() {
        let (map, _) = PageMap.build(from: Memory(items: []), canvasWidth: width)
        XCTAssertEqual(map.palette, CanvasPalette.names)
        XCTAssertTrue(map.palette.contains("ink"))
    }

    func testHeightCoversTheContent() {
        let memory = Memory(items: [text("hello", y: 900)])
        let (map, _) = PageMap.build(from: memory, canvasWidth: width)
        XCTAssertGreaterThan(map.height, 900)
    }

    func testEncodesWithTheKeysTheBackendExpects() throws {
        var item = text("hello", y: 60, size: 30)
        item.rotation = 8
        let (map, _) = PageMap.build(from: Memory(items: [item]), canvasWidth: width)
        let data = try JSONEncoder().encode(map)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let element = try XCTUnwrap((object["elements"] as? [[String: Any]])?.first)
        // The backend's ElementIn reads snake_case for this one.
        XCTAssertEqual(element["point_size"] as? Double, 30)
        XCTAssertNotNil(object["palette"])
        XCTAssertNotNil(object["omitted"])
    }
}
