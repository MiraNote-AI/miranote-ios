import XCTest
@testable import MiraNoteKit

final class PushCandidatesTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private let place = GeoPoint(lat: 32.82, lon: -96.72)

    private func at(_ day: Int, _ hour: Int = 14, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Four rich photos (spread over 3 h, favourites, faces) on a day: scores well above 0.40.
    private func fragment(on date: Int = 10, count: Int = 4, unique: Int? = nil, spacing: Int = 60) -> Fragment {
        let photos = (0..<count).map {
            GroupablePhoto(id: "d\(date)p\($0)", takenAt: at(date).addingTimeInterval(Double($0 * spacing) * 60),
                           location: place, burstId: nil)
        }
        let dupes = count - (unique ?? count)
        let rep = Dictionary(uniqueKeysWithValues: photos.suffix(dupes).map { ($0.id, photos[0].id) })
        return Fragment(photos: photos, uniqueCount: unique ?? count, representative: rep,
                        belongsTo: String(format: "2026-10-%02d", date))
    }

    private func library(_ fragment: Fragment) -> [String: LibraryAsset] {
        Dictionary(uniqueKeysWithValues: fragment.photos.map {
            ($0.id, LibraryAsset(id: $0.id, takenAt: $0.takenAt, location: $0.location, isFavorite: true,
                                 isEdited: false, isScreenshot: false, isHidden: false, isVideo: false,
                                 originalFilename: "IMG.HEIC", burstId: nil))
        })
    }

    private func analyses(_ fragment: Fragment, broad: Set<BroadCategory> = [.sky], faces: Int = 2)
        -> [String: PhotoAnalysis] {
        Dictionary(uniqueKeysWithValues: fragment.photos.map {
            ($0.id, PhotoAnalysis(id: $0.id, labels: [], broad: broad, faces: faces, aesthetics: 0.8,
                                  isUtility: false, featurePrint: nil))
        })
    }

    private func evaluate(_ fragment: Fragment, slot: Date? = nil, bucket: PushBucket = .scenery,
                          pushed: Set<String> = [], pushedPhotos: Set<String> = [],
                          prefs: PushPreferences = PushPreferences(),
                          faces: Int = 2, cache: @escaping (String) -> AIVerdict? = { _ in nil })
        -> Result<PushCandidate, Ineligible> {
        PushCandidates.evaluate(
            fragment, bucket: bucket, aiPhotoIds: fragment.photos.map(\.id), at: slot ?? at(12, 21),
            analyses: analyses(fragment, faces: faces), library: library(fragment), calendar: calendar,
            pastLocations: [], pushedDays: pushed, pushedPhotos: pushedPhotos, preferences: prefs, cache: cache)
    }

    /// Day keys are local dates of the zone that wrote them: the photos of a
    /// delivered or blocked push rule a group out whatever day it falls on now.
    func testPhotosOfAPushedOrBlockedPushRuleTheGroupOut() {
        let frag = fragment()
        XCTAssertEqual(failure(evaluate(frag, pushedPhotos: ["d10p2"])), .pushedDay)
        XCTAssertNil(failure(evaluate(frag, pushedPhotos: ["d11p2"])))
        let blocked = PushPreferences(blockedDays: ["2026-10-09": at(9)], blockedPhotos: ["2026-10-09": ["d10p0"]])
        XCTAssertEqual(failure(evaluate(frag, prefs: blocked)), .blockedDay)
    }

    private func failure(_ result: Result<PushCandidate, Ineligible>) -> Ineligible? {
        if case .failure(let reason) = result { return reason }
        return nil
    }

    func testTwoPhotosOutThreeIn() {
        XCTAssertEqual(failure(evaluate(fragment(count: 2))), .tooFewPhotos)
        XCTAssertEqual(failure(evaluate(fragment(count: 4, unique: 2))), .tooFewPhotos)
        XCTAssertNil(failure(evaluate(fragment(count: 3))))
    }

    func testTooRecentAndTooOld() {
        let frag = fragment(on: 12, count: 3, spacing: 10)
        XCTAssertEqual(failure(evaluate(frag, slot: frag.end.addingTimeInterval(11 * 3600))), .tooRecent)
        XCTAssertNil(failure(evaluate(frag, slot: at(13, 21))))
        let old = fragment(on: 1)
        let late = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 21))!
        XCTAssertEqual(failure(evaluate(old, slot: late)), .tooOld)
    }

    func testScoreBarAtPointFour() {
        // An unmarked, faceless, one-moment group, late in the window.
        let frag = fragment(count: 3, spacing: 1)
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 21))!
        let result = PushCandidates.evaluate(
            frag, bucket: .scenery, aiPhotoIds: [], at: late,
            analyses: [:], library: [:], calendar: calendar, pastLocations: [], pushedDays: [],
            preferences: PushPreferences(), cache: { _ in nil })
        XCTAssertEqual(failure(result), .lowScore)
        guard case .success(let ok) = evaluate(fragment()) else { return XCTFail("the default group passes") }
        XCTAssertGreaterThanOrEqual(ok.score.total, 0.40)
    }

    func testPushedDayExcludesItsOtherGroups() {
        XCTAssertEqual(failure(evaluate(fragment(on: 10), pushed: ["2026-10-10"])), .pushedDay)
        XCTAssertNil(failure(evaluate(fragment(on: 10), pushed: ["2026-10-09"])))
    }

    func testOnlyScheduledIsNotPushed() {
        let scheduled = PushLedgerTests.entry(day: "2026-10-10", at: at(12, 21))
        var delivered = PushLedgerTests.entry("B", day: "2026-10-09", at: at(11, 21))
        delivered.deliveredAt = at(11, 21)
        let pushed = LedgerReconciler.pushedDays([scheduled, delivered])
        XCTAssertNil(failure(evaluate(fragment(on: 10), pushed: pushed)))
        XCTAssertEqual(failure(evaluate(fragment(on: 9), pushed: pushed)), .pushedDay)
    }

    func testBlockedDayIsOut() {
        let prefs = PushPreferences(blockedDays: ["2026-10-10": at(11)])
        XCTAssertEqual(failure(evaluate(fragment(on: 10), prefs: prefs)), .blockedDay)
    }

    func testFewerBucketOutThenReduced() {
        let slot = at(12, 21)
        let blocked = PushPreferences(fewer: [.scenery: slot.addingTimeInterval(-10 * 86_400)])
        XCTAssertEqual(failure(evaluate(fragment(), slot: slot, prefs: blocked)), .bucketCooldown)
        let reduced = PushPreferences(fewer: [.scenery: slot.addingTimeInterval(-31 * 86_400)])
        guard case .success(let ok) = evaluate(fragment(), slot: slot, prefs: reduced) else {
            return XCTFail("should be eligible at x0.6")
        }
        XCTAssertEqual(ok.score.multiplier, 0.6)
    }

    func testCachedRejectedIsSkipped() {
        let verdict = AIVerdict.rejected(reason: "r", message: "m")
        XCTAssertEqual(failure(evaluate(fragment(), cache: { _ in verdict })), .aiRejected)
    }

    func testRankedSortsByTotalThenDay() {
        let first = fragment(on: 10), second = fragment(on: 9)
        var analysis = analyses(first).merging(analyses(second)) { first, _ in first }
        analysis = analysis.mapValues { $0 }
        let ranked = PushCandidates.ranked(
            [first, second], aiPhotoIds: { $0.photos.map(\.id) }, at: at(12, 21), analyses: analysis,
            library: library(first).merging(library(second)) { first, _ in first }, calendar: calendar,
            pastLocations: [], pushedDays: [], preferences: PushPreferences(), cache: { _ in nil })
        XCTAssertEqual(ranked.count, 2)
        XCTAssertGreaterThanOrEqual(ranked[0].score.total, ranked[1].score.total)
    }

    private func candidate(_ day: Int, total: Double, key: String) -> PushCandidate {
        let belongs = String(format: "2026-10-%02d", day)
        let score = FragmentScore(r: 1, s: 1, p: 1, n: 1, u: 1, a: 1, base: total, multiplier: 1, bucket: .food,
                                  total: total, days: 3, pushable: true)
        let fragment = Fragment(photos: [], uniqueCount: 3, representative: [:], belongsTo: belongs)
        return PushCandidate(fragment: fragment, groupKey: "\(belongs)_\(key)", belongsTo: belongs, bucket: .food,
                             score: score, aiPhotoIds: [], cacheKey: key)
    }

    func testEqualTotalsGoToTheEarlierDayThenTheGroupKey() {
        let best = candidate(12, total: 0.9, key: "z")
        let earlierB = candidate(5, total: 0.6, key: "b")
        let earlierA = candidate(5, total: 0.6, key: "a")
        let later = candidate(8, total: 0.6, key: "a")
        let sorted = [later, earlierB, best, earlierA].sorted(by: PushCandidates.isRankedBefore)
        XCTAssertEqual(sorted.map(\.groupKey), ["2026-10-12_z", "2026-10-05_a", "2026-10-05_b", "2026-10-08_a"])
    }
}
