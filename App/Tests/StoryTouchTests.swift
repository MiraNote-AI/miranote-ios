import XCTest
@testable import MiraNote

/// A finger on the story: down pauses, the lift decides -- and a touch the
/// system takes away (a call, Control Center, the app leaving) never lifts,
/// so it must end like a hold and let the story play on.
final class StoryTouchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let width: CGFloat = 390

    private func lift(after seconds: TimeInterval, dx: CGFloat = 0, dy: CGFloat = 0,
                      x: CGFloat = 300) -> StoryTouch.Outcome? {
        var touch = StoryTouch()
        XCTAssertTrue(touch.down(at: start))
        return touch.lift(at: start.addingTimeInterval(seconds), translation: CGSize(width: dx, height: dy),
                          x: x, width: width)
    }

    func testOnlyTheFirstMovePauses() {
        var touch = StoryTouch()
        XCTAssertTrue(touch.down(at: start))
        XCTAssertFalse(touch.down(at: start.addingTimeInterval(0.1)))
    }

    func testQuickTapsStep() {
        XCTAssertEqual(lift(after: 0.1, x: 300), .forward)
        XCTAssertEqual(lift(after: 0.1, x: 60), .back)
    }

    func testSwipesStep() {
        XCTAssertEqual(lift(after: 0.4, dx: -120), .forward)
        XCTAssertEqual(lift(after: 0.4, dx: 120), .back)
    }

    func testHoldResumes() {
        XCTAssertEqual(lift(after: 1.5), .resume)
    }

    func testATouchTakenAwayResumes() {
        var touch = StoryTouch()
        XCTAssertTrue(touch.down(at: start))
        XCTAssertEqual(touch.cancel(), .resume, "the story must not stay paused")
        XCTAssertNil(touch.lift(at: start.addingTimeInterval(2), translation: .zero, x: 300, width: width),
                     "that touch is over")
        XCTAssertTrue(touch.down(at: start.addingTimeInterval(3)), "the next touch pauses again")
    }

    func testNoTouchNothingToResume() {
        var touch = StoryTouch()
        XCTAssertNil(touch.cancel())
        XCTAssertEqual(lift(after: 0.1), .forward)
        var lifted = StoryTouch()
        _ = lifted.down(at: start)
        _ = lifted.lift(at: start.addingTimeInterval(0.1), translation: .zero, x: 300, width: width)
        XCTAssertNil(lifted.cancel(), "a lifted touch is not cancelled after")
    }
}
