import XCTest
@testable import MiraNote

/// #206, design X: how a page folds up onto its band, and opens again.
final class FoldPlanTests: XCTestCase {
    /// The prototype's band (row 1): the top pleat, the bottom pleat, then
    /// the pair; it opens the pair, the top pleat, then the bottom pleat.
    func testThePrototypesBandFoldsAndOpensAsThePrototypeDoes() {
        let plan = FoldPlan(row: 1)
        XCTAssertEqual(plan.folds.map(\.crease), [70, 210, 140])
        XCTAssertEqual(plan.folds.map(\.above), [true, false, false])
        XCTAssertEqual(plan.openOrder, [2, 0, 1])
    }

    /// Every row folds the other three rows away, outer rows first on each
    /// side, and opens a fold only once the packet holding it is open.
    func testEveryBandFoldsOuterFirstAndOpensInnerFirst() {
        for row in 0..<4 {
            let plan = FoldPlan(row: row)
            XCTAssertEqual(plan.folds.count, 3, "row \(row)")
            let turned = Set(plan.folds.flatMap { Array($0.rows) })
            XCTAssertEqual(turned, Set((0..<4).filter { $0 != row }), "row \(row) keeps only its band")
            for (index, fold) in plan.folds.enumerated() {
                let holding = plan.folds.indices.filter { other in
                    other != index && plan.folds[other].rows.contains(fold.rows.lowerBound)
                        && plan.folds[other].rows.count > fold.rows.count
                }
                for outer in holding {
                    XCTAssertGreaterThan(outer, index, "row \(row): the inner fold \(index) folds first")
                    XCTAssertLessThan(plan.openOrder.firstIndex(of: outer)!, plan.openOrder.firstIndex(of: index)!,
                                      "row \(row): the packet opens before the fold inside it")
                }
            }
        }
    }
}
