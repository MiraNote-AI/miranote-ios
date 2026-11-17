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

    func testTheFoldKeepsTheDemosBeats() {
        let beats = [0, StarFold.shrinkEnd, StarFold.cutEnd, StarFold.windEnd, StarFold.pinchEnd,
                     StarFold.land, StarFold.end]
        XCTAssertEqual(beats, beats.sorted(), "in order")
        XCTAssertLessThan(StarFold.throwStart, StarFold.pinchEnd, "the throw overlaps the pinch")
        XCTAssertEqual(StarFold.end, 1620)
        XCTAssertLessThanOrEqual(StarFold.haptics.count + 1, 3, "three haptics at most, the landing's included")
        XCTAssertLessThanOrEqual(StarUnfold.haptics.count, 3)
        XCTAssertEqual([StarUnfold.riseEnd, StarUnfold.unwindEnd, StarUnfold.dockEnd, StarUnfold.unrollEnd],
                       [StarUnfold.riseEnd, StarUnfold.unwindEnd, StarUnfold.dockEnd, StarUnfold.unrollEnd].sorted())
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

    func testTensionBuildsFrom120To350ms() {
        XCTAssertEqual(StarHold.tension(held: 0.1), 0)
        XCTAssertEqual(StarHold.tension(held: 0.235), 0.5, accuracy: 0.001)
        XCTAssertEqual(StarHold.tension(held: 0.5), 1)
    }
}
