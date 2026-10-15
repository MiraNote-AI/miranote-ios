import XCTest
@testable import MiraNote

/// App-target smoke test; the substantive coverage lives in
/// MiraNoteKit/Tests (run via `swift test`).
final class MiraNoteAppTests: XCTestCase {
    @MainActor
    func testAppRootExists() {
        XCTAssertNotNil(MiraNoteApp.self)
    }

    // In the Mira fields only a trailing new line is Return: pasted lines
    // (or a transcript with a line break) are never sent by themselves.
    func testOnlyATrailingNewLineSendsTheMiraQuestion() {
        XCTAssertEqual(ReturnKey.pressed(in: "polish this\n"), "polish this")
        XCTAssertNil(ReturnKey.pressed(in: "line one\nline two"))
        XCTAssertNil(ReturnKey.pressed(in: "no return"))
    }

    // Curated set 03 still renders in Merriweather from its static faces:
    // Regular for the body of a page, Bold where bold is asked for.
    func testMerriweatherRendersFromItsStaticFaces() {
        let regular = TextFace.uiFont(name: "Merriweather", size: 20)
        XCTAssertEqual(regular.familyName, "Merriweather")
        XCTAssertFalse(regular.fontDescriptor.symbolicTraits.contains(.traitBold))
        let bold = TextFace.uiFont(name: "Merriweather", size: 20, weight: 700)
        XCTAssertEqual(bold.familyName, "Merriweather")
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    // The composer's bottom follows the safe area: 36 above the edge with a
    // home indicator (34 + 2), 16 without one, 10 above a keyboard.
    func testTheEditorsBottomGapFollowsTheSafeArea() {
        XCTAssertEqual(Metrics.bottomGap(safeAreaBottom: 34), 2)
        XCTAssertEqual(Metrics.bottomGap(safeAreaBottom: 0), 16)
        XCTAssertEqual(Metrics.bottomGap(safeAreaBottom: 336), 10)
    }
}
