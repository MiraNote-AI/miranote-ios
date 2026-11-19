import XCTest
@testable import MiraNoteKit

/// #206: when a Save folds its page into a star, and how a press on a
/// jar star becomes a shake, a cancel or an open.
final class StarMotionTests: XCTestCase {
    // MARK: First Save only

    func testOnlyTheFirstSaveOntoHomeFolds() {
        XCTAssertEqual(StarFold.arrival(saved: true, wasStar: false, onHome: true, reduceMotion: false), .fold)
        XCTAssertEqual(StarFold.arrival(saved: true, wasStar: true, onHome: true, reduceMotion: false), .none,
                       "a re-save of a star")
        XCTAssertEqual(StarFold.arrival(saved: false, wasStar: false, onHome: true, reduceMotion: false), .none,
                       "Back or autosave keeps a draft")
        XCTAssertEqual(StarFold.arrival(saved: true, wasStar: false, onHome: false, reduceMotion: false), .none,
                       "no jar on screen")
        XCTAssertEqual(StarFold.arrival(saved: true, wasStar: false, onHome: true, reduceMotion: true), .glow)
    }

    /// The fold demo v4's save: shrink 0-180, cut 180-400, wind 400-780,
    /// pinch from 780, thrown from 880, in the jar at 1320, over at 1620.
    func testTheFoldShowsTheDemosBeatsAtTheirTimes() {
        let expected: [(Double, StarFold.Beat)] = [
            (0, .shrink), (179, .shrink), (180, .cut), (399, .cut), (400, .wind), (779, .wind),
            (780, .pinch), (879, .pinch), (880, .throw), (1319, .throw), (1320, .landed), (1619, .landed),
            (1620, .done)
        ]
        for (ms, beat) in expected { XCTAssertEqual(StarFold.beat(at: ms), beat, "at \(ms) ms") }
        XCTAssertLessThan(StarFold.haptics.count + 1, 4, "at most three haptics, the landing's included")
        XCTAssertTrue(StarFold.haptics.allSatisfy { StarFold.beat(at: $0) != .done }, "all during the fold")
    }

    /// The open after the commit: rise to 210, unwind to 470, dock to
    /// 630, unroll to 770, then the page opens.
    func testTheOpenShowsTheDemosBeatsAtTheirTimes() {
        let expected: [(Double, StarUnfold.Beat)] = [
            (0, .rise), (209, .rise), (210, .unwind), (469, .unwind), (470, .dock), (629, .dock),
            (630, .unroll), (769, .unroll), (770, .open)
        ]
        for (ms, beat) in expected { XCTAssertEqual(StarUnfold.beat(at: ms), beat, "at \(ms) ms") }
        XCTAssertEqual(StarUnfold.beat(at: StarUnfold.haptics[1]), .dock, "the second haptic as the strip docks")
    }

    // MARK: Hold

    func testAQuickTapShakes() {
        var hold = StarHold()
        hold.down(at: 10)
        XCTAssertEqual(hold.tick(at: 10.05), .none)
        XCTAssertEqual(hold.up(at: 10.1), .shake)
    }

    func testLettingGoDuringTheTensionCancelsSilently() {
        var hold = StarHold()
        hold.down(at: 0)
        XCTAssertEqual(hold.tick(at: 0.2), .none)
        XCTAssertEqual(hold.up(at: 0.2), .cancel)
        XCTAssertFalse(hold.isPressing)
    }

    func testHoldingCommitsAt350ms() {
        var hold = StarHold()
        hold.down(at: 0)
        XCTAssertEqual(hold.tick(at: 0.349), .none)
        XCTAssertEqual(hold.tick(at: 0.35), .commit)
        XCTAssertEqual(hold.tick(at: 0.4), .none, "once")
        XCTAssertEqual(hold.up(at: 0.5), .none, "the finger may lift: the open goes on")
    }

    func testALateClockStillCommitsOnRelease() {
        var hold = StarHold()
        hold.down(at: 0)
        XCTAssertEqual(hold.up(at: 0.36), .commit)
    }

    func testSlidingTenPointsCancels() {
        var hold = StarHold()
        hold.down(at: 0)
        XCTAssertEqual(hold.moved(9.9), .none)
        XCTAssertEqual(hold.moved(10.5), .cancel)
        XCTAssertEqual(hold.tick(at: 0.4), .none, "a cancelled hold never opens")
        XCTAssertEqual(hold.up(at: 0.5), .none)
    }

    func testACancelledPressNeverOpensAndTheNextPressWorks() {
        var hold = StarHold()
        hold.down(at: 0)
        XCTAssertTrue(hold.reset(), "a hold still gathering springs back")
        XCTAssertEqual(hold.tick(at: 0.4), .none, "the timer cannot open it")
        XCTAssertFalse(hold.reset(), "nothing left to spring back")
        hold.down(at: 1)
        XCTAssertEqual(hold.up(at: 1.05), .shake, "the next tap shakes")
    }

    func testTensionBuildsFrom120To350ms() {
        XCTAssertEqual(StarHold.tension(held: 0.1), 0)
        XCTAssertEqual(StarHold.tension(held: 0.235), 0.5, accuracy: 0.001)
        XCTAssertEqual(StarHold.tension(held: 0.5), 1)
    }
}
