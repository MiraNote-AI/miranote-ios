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
        XCTAssertEqual(StarFold.arrival(saved: true, wasStar: false, onHome: true, reduceMotion: true), .fade)
    }

    /// Design X's save: half-fold to 280, pleats to 600, tie to 680, wind
    /// to 1000, puff to 1200, the drop lands at 1440, the dock from 1590,
    /// over at 1800.
    func testTheFoldShowsDesignXsBeatsAtTheirTimes() {
        let expected: [(Double, StarFold.Beat)] = [
            (0, .halfFold), (279, .halfFold), (280, .pleats), (599, .pleats), (600, .tie), (679, .tie),
            (680, .wind), (999, .wind), (1000, .puff), (1199, .puff), (1200, .toss), (1439, .toss),
            (1440, .landed), (1589, .landed), (1590, .dock), (1799, .dock), (1800, .done)
        ]
        for (ms, beat) in expected { XCTAssertEqual(StarFold.beat(at: ms), beat, "at \(ms) ms") }
        XCTAssertLessThanOrEqual(StarFold.end, 1800, "Save stays within 1.8 s")
    }

    func testTheFoldsHapticsLandOnItsBeats() {
        let haptics = StarFold.haptics
        XCTAssertEqual(haptics.map(\.ms), haptics.map(\.ms).sorted(), "in time order")
        XCTAssertTrue(haptics.allSatisfy { $0.ms < StarFold.end }, "all during the fold")
        XCTAssertEqual(haptics.first, StarHaptic(0, .light, 1), "the tap")
        XCTAssertTrue(haptics.contains(StarHaptic(270, .rigid, 0.6)), "the half-fold lands")
        XCTAssertTrue(haptics.contains(StarHaptic(1040, .medium, 0.8)), "the puff")
        XCTAssertTrue(haptics.contains(StarHaptic(StarFold.land, .rigid, 0.7)), "the star lands")
        let rolls = haptics.filter { StarFold.beat(at: $0.ms) == .wind && $0.style == .soft }
        XCTAssertEqual(rolls.count, 4, "the rolls tick")
    }

    /// Design X's open after the commit: cap to 150, lift to 400, unpuff
    /// to 490, unwind to 840, pleats to 990, the half to 1140, the fill to
    /// the reading page, readable at 1400.
    func testTheOpenShowsDesignXsBeatsAtTheirTimes() {
        let expected: [(Double, StarUnfold.Beat)] = [
            (0, .cap), (149, .cap), (150, .lift), (399, .lift), (400, .unpuff), (489, .unpuff),
            (490, .unwind), (839, .unwind), (840, .pleats), (989, .pleats), (990, .half), (1139, .half),
            (1140, .fill), (1399, .fill), (1400, .open)
        ]
        for (ms, beat) in expected { XCTAssertEqual(StarUnfold.beat(at: ms), beat, "at \(ms) ms") }
        XCTAssertLessThanOrEqual(StarUnfold.end, 1400, "readable within 1.4 s of the commit")
        XCTAssertEqual(StarUnfold.haptics.first, StarHaptic(0, .medium, 0.8), "the commit")
        XCTAssertEqual(StarUnfold.haptics.last?.ms, StarUnfold.end, "readable")
        XCTAssertEqual(StarUnfold.beat(at: StarUnfold.haptics[1].ms), .cap, "the cap comes off")
    }

    func testReduceMotionIsAShortCrossFade() {
        XCTAssertEqual(StarFold.fadeEnd, 500)
        XCTAssertLessThan(StarFold.fadeToStar, StarFold.fadeEnd)
        XCTAssertEqual(StarFold.fadeHaptics.map(\.style), [.soft])
        XCTAssertEqual(StarUnfold.fade, 400)
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
