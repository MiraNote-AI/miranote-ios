import XCTest
@testable import MiraNoteKit

/// Preselection (acceptance B3): steps 1-5 of the v1 preselection rule on made-up
/// photos, one test per step.
final class PreselectorTests: XCTestCase {
    private typealias Spec = Scenario.Spec

    /// A made-up fragment: photos by minute, their analysis and marks.
    private struct Scenario {
        let start = Date(timeIntervalSince1970: 1_760_800_000)

        struct Spec {
            var minute: Double
            var aesthetics: Double?
            var faces = 0
            var broad: Set<BroadCategory> = []
            var favorite = false
        }

        var specs: [String: Spec] = [:]
        var order: [String] = []
        var representative: [String: String] = [:]
        var distances: [Set<String>: Float] = [:]

        mutating func add(_ id: String, _ spec: Spec) {
            specs[id] = spec
            order.append(id)
        }

        func fragment() -> Fragment {
            let photos = order.map {
                GroupablePhoto(id: $0, takenAt: start.addingTimeInterval(specs[$0]!.minute * 60), location: nil,
                               burstId: nil)
            }.sorted { $0.takenAt < $1.takenAt }
            return Fragment(photos: photos, uniqueCount: photos.count - representative.count,
                            representative: representative, belongsTo: "2026-10-18")
        }

        func select() -> [Preselected] {
            let fragment = fragment()
            let analyses = specs.keys.reduce(into: [String: PhotoAnalysis]()) { result, id in
                let spec = specs[id]!
                result[id] = PhotoAnalysis(id: id, labels: [], broad: spec.broad, faces: spec.faces,
                                           aesthetics: spec.aesthetics, isUtility: false, featurePrint: nil)
            }
            let library = specs.keys.reduce(into: [String: LibraryAsset]()) { result, id in
                result[id] = LibraryAsset(id: id, takenAt: nil, location: nil, isFavorite: specs[id]!.favorite,
                                          isEdited: false, isScreenshot: false, isHidden: false, isVideo: false,
                                          originalFilename: nil, burstId: nil)
            }
            let distances = self.distances
            return Preselector.select(fragment, analyses: analyses, library: library) { first, second in
                distances[[first, second]]
            }
        }
    }

    private func reasons(_ selected: [Preselected]) -> [String: Preselected.Reason] {
        Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0.reason) })
    }

    // Step 0.
    func testTenOrFewerSendsAll() {
        var test = Scenario()
        for index in 0..<10 { test.add("p\(index)", Spec(minute: Double(index))) }
        test.add("d1", Spec(minute: 0.5))
        test.add("d2", Spec(minute: 0.7))
        test.representative = ["d1": "p0", "d2": "p0"]
        let selected = test.select()
        XCTAssertEqual(selected.map(\.id), (0..<10).map { "p\($0)" })
        XCTAssertTrue(selected.allSatisfy { $0.reason == .all })
        XCTAssertEqual(selected.first?.represents, 3)
        XCTAssertEqual(selected.last?.represents, 1)
    }

    // Step 1.
    func testAtMostThreeMarked() {
        var test = Scenario()
        for index in 0..<15 {
            let spec = Spec(minute: Double(index), aesthetics: Double(index) / 20, favorite: index < 5)
            test.add("p\(index)", spec)
        }
        let selected = test.select()
        let marked = selected.filter { $0.reason == .marked }.map(\.id)
        XCTAssertEqual(Set(marked), ["p2", "p3", "p4"], "the three best-scoring marked photos")
        XCTAssertEqual(selected.count, 10)
    }

    // Step 2.
    func testFirstAndLastMomentKept() {
        var test = Scenario()
        // Twelve moments 30 minutes apart; moment 5 has three photos.
        for moment in 0..<12 { test.add("m\(moment)", Spec(minute: Double(moment) * 30)) }
        test.add("m5b", Spec(minute: 151, aesthetics: 0.9))
        test.add("m5c", Spec(minute: 152))
        let selected = test.select()
        let moments = selected.filter { $0.reason == .moment }.map(\.id)
        XCTAssertEqual(moments.count, 10, "one per moment until the slots run out")
        XCTAssertTrue(moments.contains("m0"))
        XCTAssertTrue(moments.contains("m11"))
        XCTAssertTrue(moments.contains("m5b"), "the busiest moment, by its best photo")
        XCTAssertFalse(moments.contains("m5"))
    }

    // Step 3.
    func testCategoryPriorityOrder() {
        var test = Scenario()
        test.add("p0", Spec(minute: 0, aesthetics: 1, broad: [.built]))
        test.add("p1", Spec(minute: 1, broad: [.art]))
        test.add("p2", Spec(minute: 2, broad: [.sky]))
        test.add("p3", Spec(minute: 3, broad: [.food_drink]))
        test.add("p4", Spec(minute: 4, broad: [.animal]))
        test.add("p5", Spec(minute: 5, broad: [.people]))
        test.add("p6", Spec(minute: 6, broad: [.plant]))
        test.add("p7", Spec(minute: 7, broad: [.event]))
        for index in 8..<14 { test.add("p\(index)", Spec(minute: Double(index))) }
        let reasons = reasons(test.select())
        XCTAssertEqual(reasons["p0"], .moment)
        XCTAssertEqual(Set(reasons.filter { $0.value == .newCategory }.keys), ["p5", "p4", "p3", "p7"],
                       "people, animals, then food and events; at most four")
        XCTAssertNotEqual(reasons["p2"], .newCategory)
        XCTAssertNotEqual(reasons["p1"], .newCategory)
    }

    // Step 4.
    func testPersonFloorAndSecondDissimilarPerson() {
        var test = Scenario()
        test.add("p0", Spec(minute: 0, aesthetics: 1))
        for index in 1..<11 { test.add("p\(index)", Spec(minute: Double(index))) }
        test.add("f1", Spec(minute: 11, faces: 1))
        test.add("f2", Spec(minute: 12, faces: 2))
        test.add("f3", Spec(minute: 13, faces: 1))
        test.distances = [["f1", "f2"]: 0.1, ["f1", "f3"]: 0.8, ["f2", "f3"]: 0.75]
        let reasons = reasons(test.select())
        XCTAssertEqual(reasons["f1"], .person, "the floor: the best person photo, the earliest on a tie")
        XCTAssertEqual(reasons["f3"], .person, "and the person photo least like it")
        XCTAssertNotEqual(reasons["f2"], .person)
    }

    // Step 5.
    func testFillUsesMmr() {
        var test = Scenario()
        test.add("p0", Spec(minute: 0, aesthetics: 1))
        let alike = (1...8).map { "a\($0)" }
        let different = (1...6).map { "z\($0)" }
        for (index, id) in alike.enumerated() {
            test.add(id, Spec(minute: Double(index + 1), aesthetics: 0.9))
        }
        for (index, id) in different.enumerated() {
            test.add(id, Spec(minute: Double(index + 10), aesthetics: -1))
        }
        for first in ["p0"] + alike {
            for second in ["p0"] + alike where first != second { test.distances[[first, second]] = 0.05 }
        }
        let selected = test.select()
        XCTAssertEqual(selected.count, 10)
        let ids = Set(selected.map(\.id))
        XCTAssertTrue(Set(different).isSubset(of: ids), "unlike photos win over near-copies of the best")
        XCTAssertTrue(selected.filter { $0.id != "p0" }.allSatisfy { $0.reason == .fill })
    }

    func testOutputIsTimeOrdered() {
        var test = Scenario()
        for index in 0..<20 {
            test.add("p\(index)", Spec(minute: Double((index * 7) % 20) * 25, aesthetics: Double(index % 5) / 5,
                                       faces: index % 6 == 0 ? 2 : 0, broad: index % 4 == 0 ? [.sky] : []))
        }
        let selected = test.select()
        let minutes = selected.map { test.specs[$0.id]!.minute }
        XCTAssertEqual(minutes, minutes.sorted())
        XCTAssertEqual(selected.count, 10)
        XCTAssertEqual(Set(selected.map(\.id)).count, 10)
    }

    func testOnlyUniquePhotosAreSent() {
        var test = Scenario()
        for index in 0..<12 { test.add("p\(index)", Spec(minute: Double(index), aesthetics: 1)) }
        test.add("d0", Spec(minute: 0.5, aesthetics: 1))
        test.representative = ["d0": "p0"]
        let selected = test.select()
        XCTAssertFalse(selected.map(\.id).contains("d0"))
        XCTAssertEqual(selected.first { $0.id == "p0" }?.represents ?? 2, 2)
    }
}
