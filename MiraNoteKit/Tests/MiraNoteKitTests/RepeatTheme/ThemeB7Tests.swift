import Foundation
import XCTest
@testable import MiraNoteKit

/// Compares the phone's pile cut with the desktop reference script and with
/// the user's own food ticks, on the user's B7 photo set. The data stays on
/// that one Mac: set `MIRANOTE_B7_VISION` (the Vision records, one JSON
/// object per line) and `MIRANOTE_B7_TRUTH` (the ticked food truth) to run;
/// everywhere else the tests skip.
final class ThemeB7Tests: XCTestCase {
    private struct Library {
        let kept: [ThemePhoto]
        let moments: [Moment]
        let piles: [Pile]
        let truth: [String: [String]]

        func photos(of pile: Pile) -> [String] {
            let byId = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
            return pile.momentIds.flatMap { byId[$0]?.photoIds ?? [] }
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func load() throws -> Library {
        let environment = ProcessInfo.processInfo.environment
        guard let visionPath = environment["MIRANOTE_B7_VISION"],
              let truthPath = environment["MIRANOTE_B7_TRUTH"] else {
            throw XCTSkip("set MIRANOTE_B7_VISION and MIRANOTE_B7_TRUTH to compare with the B7 reference cut")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        let text = try String(contentsOfFile: visionPath, encoding: .utf8)
        var kept: [ThemePhoto] = []
        for line in text.split(separator: "\n") where !line.isEmpty {
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            // The reference script's filter: no utility shots, a camera make, a date.
            if record["utility"] as? Bool == true { continue }
            guard let make = record["make"] as? String, !make.isEmpty,
                  let date = record["date"] as? String, !date.isEmpty else { continue }
            let takenAt = try XCTUnwrap(formatter.date(from: String(date.prefix(19))), date)
            let print = try XCTUnwrap(record["fp"] as? [Double]).map { Float($0) }
            let labels = (record["labels"] as? [[Any]] ?? []).compactMap { pair -> LabelScore? in
                guard let id = pair.first as? String, let confidence = pair.last as? Double else { return nil }
                return LabelScore(id: id, confidence: Float(confidence))
            }
            kept.append(ThemePhoto(id: try XCTUnwrap(record["file"] as? String), takenAt: takenAt, location: nil,
                                   labels: labels, aesthetics: record["aes"] as? Double, faces: 0, isTheme: true,
                                   print: ThemePhoto.normalized(print), printRevision: 0))
        }
        let truthData = try Data(contentsOf: URL(fileURLWithPath: truthPath))
        let truth = try XCTUnwrap(JSONSerialization.jsonObject(with: truthData) as? [String: [String]])

        let moments = MomentBuilder.build(kept, calendar: calendar)
        let piles = PileCutter.cut(moments, tree: ThemeTree.build(moments.map(\.vector)))
        return Library(kept: kept, moments: moments, piles: piles, truth: truth)
    }

    /// B4a: the same piles as the reference script (j_cut.py, re-run 2026-11-21).
    func testPilesMatchReferenceCut() throws {
        let library = try load()
        let summary = library.piles.map { pile in
            (days: pile.days, moments: pile.momentIds.count, photos: library.photos(of: pile).count)
        }
        for (pile, row) in zip(library.piles, summary) {
            print("ThemeB7Tests: pile \(row.days) days / \(row.moments) moments / \(row.photos) photos, "
                  + "max day share \(String(format: "%.3f", pile.maxDayShare)), "
                  + "height \(String(format: "%.4f", pile.height))")
        }
        print("ThemeB7Tests: \(library.kept.count) kept, \(library.moments.count) moments, "
              + "\(library.piles.count) piles")

        XCTAssertEqual(library.kept.count, 301)
        XCTAssertEqual(library.moments.count, 152)
        XCTAssertEqual(library.piles.count, 5)
        let rows = summary.map { [$0.days, $0.moments, $0.photos] }
            .sorted { ($0[0], $0[1], $0[2]) > ($1[0], $1[1], $1[2]) }
        XCTAssertEqual(rows, [[28, 50, 57], [8, 8, 12], [7, 7, 13], [5, 5, 8], [5, 5, 7]])

        let food = try XCTUnwrap(library.piles.first)
        XCTAssertEqual(food.days, 28)
        XCTAssertEqual((food.maxDayShare * 100).rounded(.down), 8)
        XCTAssertEqual((Double(food.height) * 100).rounded(), 48)
    }

    /// B4b: the food pile against what the user ticked.
    func testFoodPileAgainstTruth() throws {
        let library = try load()
        let food = try XCTUnwrap(library.piles.first)
        let photos = library.photos(of: food)
        let byId = Dictionary(uniqueKeysWithValues: library.kept.map { ($0.id, $0) })

        // The truth answers per photo: the dishes seen, or one of two
        // markers. "None of these" is still a meal, just without the listed
        // dishes; "not a meal" is the only no.
        let notAMeal = "\u{4E0D}\u{662F}\u{4E00}\u{987F}\u{996D}"
        let noneOfThese = "\u{90FD}\u{6CA1}\u{6709}"
        let meals = Set(library.truth.filter { !$0.value.contains(notAMeal) }.keys)
        let withDish = Set(library.truth.filter { !Set($0.value).subtracting([notAMeal, noneOfThese]).isEmpty }.keys)
        print("ThemeB7Tests: food pile \(photos.count) photos; \(photos.filter(meals.contains).count) meals per truth, "
              + "\(photos.filter(withDish.contains).count) with a ticked dish; "
              + "\(withDish.intersection(photos).count) of \(withDish.count) ticked-dish photos are in the pile")

        let notMeals = photos.filter { !meals.contains($0) }
        // Open question for the user (2026-11-21): one food-pile photo is
        // ticked "not a meal", and j_cut.py's pile holds the same photo.
        // Remove this expectation once the user has decided.
        XCTExpectFailure("B4b open: a food-pile photo the truth marks not a meal, same as j_cut.py") {
            XCTAssertEqual(notMeals.count, 0, "food-pile photos the truth does not call a meal")
        }

        // No photo of people without any food label (confidence >= 0.3).
        let foodLabels: Set<String> = ["food", "dish", "meal", "soup", "noodle", "rice", "vegetable", "fruit",
                                       "dessert", "bread", "meat", "utensil", "tableware", "bowl"]
        let peopleNoFood = photos.filter { id in
            let strong = Set((byId[id]?.labels ?? []).filter { $0.confidence >= 0.3 }.map(\.id))
            return !strong.isDisjoint(with: ["people", "adult"]) && strong.isDisjoint(with: foodLabels)
        }
        XCTAssertEqual(peopleNoFood, [])

        // The 2026-11-11 event did not form a pile or flood another one.
        for pile in library.piles {
            let eventMoments = library.moments.filter { pile.momentIds.contains($0.id) && $0.day == "2026-11-11" }
            XCTAssertLessThanOrEqual(eventMoments.count, 4, "pile of \(pile.days) days")
        }
    }
}
