import XCTest
@testable import MiraNoteKit

/// Which photos a test push checks in round 2 (decision 12) and which of
/// the survivors it shows (decision 13).
final class PushPhotoPickerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_795_262_400)  // 2026-11-21 12:00 UTC

    private func at(_ day: Int, hour: Double = 0) -> Date {
        start.addingTimeInterval(-Double(day) * 86_400 + hour * 3600)
    }

    private func dayKey(_ day: Int) -> String { "d\(String(format: "%03d", 999 - day))" }

    private static func vector(_ values: [Float]) -> [Float] {
        let length = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return values.map { $0 / length }
    }

    /// One photo `p<day>` a day for `days`, all of the same look.
    private struct Photos {
        var ids: [String] = []
        var takenAt: [String: Date] = [:]
        var days: [String: String] = [:]
        var aesthetics: [String: Double] = [:]
        var vectors: [String: [Float]] = [:]
    }

    private func photos(days: [Int]) -> Photos {
        var photos = Photos()
        for day in days {
            let id = "p\(day)"
            photos.ids.append(id)
            photos.takenAt[id] = at(day)
            photos.days[id] = dayKey(day)
            photos.aesthetics[id] = 0.5
            photos.vectors[id] = Self.vector([1, 0, 0])
        }
        return photos
    }

    private func candidates(_ photos: Photos, center: [Float] = [1, 0, 0],
                            lifeFragment: Set<String> = []) -> [String] {
        PushPhotoPicker.candidates(photos.ids, takenAt: photos.takenAt, days: photos.days,
                                   aesthetics: photos.aesthetics, vectors: photos.vectors, center: center,
                                   lifeFragmentPhotos: lifeFragment)
    }

    func testCandidatesOnePerDayMaxFifteenEvenlySpread() {
        // 30 days, one photo each, 1..30 days back.
        let all = photos(days: Array(1...30))
        let picked = candidates(all)
        XCTAssertEqual(picked.count, PushPhotoPicker.maxCandidates)
        XCTAssertEqual(Set(picked.compactMap { all.days[$0] }).count, picked.count, "one photo a day")
        XCTAssertEqual(picked.first, "p30", "the first day is kept")
        XCTAssertEqual(picked.last, "p1", "the last day is kept")
        XCTAssertEqual(picked, picked.sorted { all.takenAt[$0]! < all.takenAt[$1]! }, "by date")
        // Evenly over time: no gap is more than twice the even step (29 days / 14).
        let times = picked.map { all.takenAt[$0]!.timeIntervalSince1970 / 86_400 }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        XCTAssertLessThanOrEqual(gaps.max() ?? 0, 2 * 29.0 / 14 + 0.01, "\(gaps)")

        // The day's best aesthetics wins; the same aesthetics: the one nearest the center.
        var tie = photos(days: [1, 2, 3, 4, 5])
        tie.ids.append("p2-best")
        tie.takenAt["p2-best"] = at(2, hour: 1)
        tie.days["p2-best"] = dayKey(2)
        tie.aesthetics["p2-best"] = 0.9
        tie.vectors["p2-best"] = Self.vector([0, 0, 1])
        tie.ids.append("p3-far")
        tie.takenAt["p3-far"] = at(3, hour: 1)
        tie.days["p3-far"] = dayKey(3)
        tie.aesthetics["p3-far"] = 0.5
        tie.vectors["p3-far"] = Self.vector([0, 1, 0])
        tie.vectors["p3"] = Self.vector([1, 0.2, 0])
        XCTAssertEqual(candidates(tie), ["p5", "p4", "p3", "p2-best", "p1"])
        XCTAssertEqual(candidates(tie, center: [0, 1, 0]), ["p5", "p4", "p3-far", "p2-best", "p1"])
        // Under 15 days: every day.
        XCTAssertEqual(candidates(photos(days: Array(1...15))).count, 15)
    }

    /// Days a life-fragment push used go after the others, and only fill
    /// what the other days leave of the 15.
    func testCandidatesPutLifeFragmentDaysLast() {
        let all = photos(days: Array(1...20))
        let used = Set((1...8).map { "p\($0)" })
        let picked = candidates(all, lifeFragment: used)
        XCTAssertEqual(picked.count, 15)
        XCTAssertEqual(Array(picked.prefix(12)), (9...20).reversed().map { "p\($0)" }, "the other days first, by date")
        XCTAssertTrue(picked.suffix(3).allSatisfy(used.contains), "then life-fragment days")
        XCTAssertEqual(picked.suffix(3).first, "p8", "spread over their own span, first kept")
        XCTAssertEqual(picked.last, "p1", "and last kept")

        let plenty = candidates(photos(days: Array(1...40)), lifeFragment: used)
        XCTAssertEqual(plenty.count, 15)
        XCTAssertTrue(plenty.allSatisfy { !used.contains($0) }, "enough other days: none of them")
        XCTAssertEqual(plenty.first, "p40")
        XCTAssertEqual(plenty.last, "p9")
    }

    func testPickerFiveToNineDefaultSevenByDate() {
        let sorted = (1...12).reversed().map { "p\($0)" }
        var takenAt: [String: Date] = [:]
        var vectors: [String: [Float]] = [:]
        for day in 1...12 {
            takenAt["p\(day)"] = at(day)
            // All near the theme's look; days 2-6 the same shot, the others
            // each off in a direction of their own.
            var raw = [Float](repeating: 0, count: 9)
            raw[0] = 1
            if (2...6).contains(day) { raw[8] = 0.2 } else { raw[day == 1 ? 1 : day - 5] = 0.4 }
            vectors["p\(day)"] = Self.vector(raw)
        }
        let center = Self.vector([1, 0, 0, 0, 0, 0, 0, 0, 0])
        let picked = PushPhotoPicker.pick(sorted.shuffled(), vectors: vectors, takenAt: takenAt, center: center)
        XCTAssertEqual(picked.count, PushPhotoPicker.defaultCount)
        XCTAssertEqual(picked.first, "p12", "the earliest")
        XCTAssertEqual(picked.last, "p1", "and the latest are always in")
        XCTAssertEqual(picked, picked.sorted { takenAt[$0]! < takenAt[$1]! }, "by date")
        XCTAssertLessThanOrEqual(picked.filter { (2...6).map { "p\($0)" }.contains($0) }.count, 2,
                                 "look-alikes are not all taken")

        for count in [5, 6] {
            let few = Array(sorted.prefix(count))
            XCTAssertEqual(PushPhotoPicker.pick(few.reversed(), vectors: vectors, takenAt: takenAt, center: []),
                           few, "5-6 left: all of them, by date")
        }
        XCTAssertEqual(PushPhotoPicker.pick(Array(sorted.prefix(7)), vectors: vectors, takenAt: takenAt, center: [])
            .count, 7)
        XCTAssertTrue((PushPhotoPicker.minPhotos...PushPhotoPicker.maxPhotos).contains(picked.count))
    }
}
