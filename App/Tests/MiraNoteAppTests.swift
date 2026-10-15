import XCTest
@testable import MiraNote

/// App-target smoke test; the substantive coverage lives in
/// MiraNoteKit/Tests (run via `swift test`).
final class MiraNoteAppTests: XCTestCase {
    @MainActor
    func testAppRootExists() {
        XCTAssertNotNil(MiraNoteApp.self)
    }

    // The composer's bottom follows the safe area: 36 above the edge with a
    // home indicator (34 + 2), 16 without one, 10 above a keyboard.
    func testTheEditorsBottomGapFollowsTheSafeArea() {
        XCTAssertEqual(Metrics.bottomGap(safeAreaBottom: 34), 2)
        XCTAssertEqual(Metrics.bottomGap(safeAreaBottom: 0), 16)
        XCTAssertEqual(Metrics.bottomGap(safeAreaBottom: 336), 10)
    }
}
