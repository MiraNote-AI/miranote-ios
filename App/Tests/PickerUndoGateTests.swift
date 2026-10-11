import XCTest
@testable import MiraNote

final class PickerUndoGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let blockA = UUID()
    private let blockB = UUID()

    func testADragRecordsOnlyItsFirstChange() {
        var gate = PickerUndoGate()
        XCTAssertTrue(gate.shouldRecord(item: blockA, field: "color", now: start))
        XCTAssertFalse(gate.shouldRecord(item: blockA, field: "color", now: start + 0.2))
        XCTAssertFalse(gate.shouldRecord(item: blockA, field: "color", now: start + 0.4))
    }

    func testAnotherPropertyIsANewStep() {
        var gate = PickerUndoGate()
        _ = gate.shouldRecord(item: blockA, field: "color", now: start)
        XCTAssertTrue(gate.shouldRecord(item: blockA, field: "background", now: start + 0.2))
    }

    func testAnotherBlockIsANewStep() {
        var gate = PickerUndoGate()
        _ = gate.shouldRecord(item: blockA, field: "color", now: start)
        XCTAssertTrue(gate.shouldRecord(item: blockB, field: "color", now: start + 0.2))
    }

    func testALongPauseIsANewStep() {
        var gate = PickerUndoGate()
        _ = gate.shouldRecord(item: blockA, field: "color", now: start)
        XCTAssertTrue(gate.shouldRecord(
            item: blockA, field: "color", now: start + PickerUndoGate.window + 0.1))
    }

    func testResetStartsANewStep() {
        var gate = PickerUndoGate()
        _ = gate.shouldRecord(item: blockA, field: "color", now: start)
        gate.reset()
        XCTAssertTrue(gate.shouldRecord(item: blockA, field: "color", now: start + 0.2))
    }
}
