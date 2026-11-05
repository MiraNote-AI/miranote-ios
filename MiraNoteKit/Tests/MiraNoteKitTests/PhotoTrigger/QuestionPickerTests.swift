import XCTest
@testable import MiraNoteKit

/// Picking a push's question by type (handoff refine 4.3, acceptance R4).
final class QuestionPickerTests: XCTestCase {
    private typealias Question = TriggerMemory.Ending.Question

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func question(_ type: String, source: String = "llm") -> Question {
        Question(text: "Q \(type)", type: type, source: source)
    }

    /// 21:00 Chicago on November `day`, 2025.
    private func night(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 11, day: day, hour: 21))!
    }

    private func entry(_ id: String, night day: Int, type: String?) -> LedgerEntry {
        var entry = PushLedgerTests.entry(id, at: night(day))
        entry.questionType = type
        return entry
    }

    func testFirstCandidateWhenNothingIsNearby() {
        let pick = QuestionPicker.pick([question("order"), question("sound")], nearby: [])
        XCTAssertEqual(pick?.question.type, "order")
        XCTAssertEqual(pick?.clashed, false)
    }

    func testFirstCandidateWhoseTypeIsFree() {
        let pick = QuestionPicker.pick([question("order"), question("sound"), question("route")],
                                       nearby: ["order", "sound"])
        XCTAssertEqual(pick?.question.type, "route")
        XCTAssertEqual(pick?.clashed, false)
    }

    func testOtherNeverClashes() {
        let pick = QuestionPicker.pick([question("order"), question("other")], nearby: ["order", "other"])
        XCTAssertEqual(pick?.question.type, "other")
        XCTAssertEqual(pick?.clashed, false)
    }

    func testAllClashingTakesTheFirstAndSaysSo() {
        let pick = QuestionPicker.pick([question("one_word", source: "fallback_B1"),
                                        question("imagine", source: "fallback_B3")],
                                       nearby: ["imagine", "one_word"])
        XCTAssertEqual(pick?.question.source, "fallback_B1")
        XCTAssertEqual(pick?.clashed, true)
    }

    func testNoCandidatesNoPick() {
        XCTAssertNil(QuestionPicker.pick([], nearby: []))
    }

    func testPickingKeepsTheCandidates() {
        let memory = TriggerMemoryTests.memory(ids: ["01", "02", "03"], peak: "01")
        let asked = TriggerMemory(
            id: "m", date: memory.date, daypart: memory.daypart, push: memory.push, story: memory.story,
            ending: .init(factLine: "f", detail: "d", questions: [question("zoom"), question("order")],
                          ctaLabel: "c"))
        XCTAssertEqual(asked.ending.questionType, "zoom", "the backend's first until a night picks")
        let (picked, clashed) = QuestionPicker.picking(asked, nearby: ["zoom"])
        XCTAssertFalse(clashed)
        XCTAssertEqual(picked.ending.question, "Q order")
        XCTAssertEqual(picked.ending.questionType, "order")
        XCTAssertEqual(picked.ending.questionSource, "llm")
        XCTAssertEqual(picked.ending.questions.map(\.type), ["zoom", "order"])
        XCTAssertEqual(picked.ending.otherQuestions.map(\.type), ["zoom"])
        XCTAssertEqual(picked.ending.detail, "d")
    }

    /// Two nights either side, the night itself left out, one per night.
    func testNearbyTypesAreTheTwoNightsEitherSide() {
        let entries = [
            entry("a", night: 3, type: "far"), entry("b", night: 4, type: "order"),
            entry("c", night: 5, type: "sound"), entry("d", night: 6, type: "self"),
            entry("e", night: 7, type: "route"), entry("f", night: 8, type: "zoom"),
            entry("g", night: 9, type: "far")
        ]
        XCTAssertEqual(QuestionPicker.nearbyTypes(entries, around: night(6), calendar: calendar),
                       ["order", "sound", "route", "zoom"])
        XCTAssertEqual(QuestionPicker.nearbyTypes(entries, around: calendar.startOfDay(for: night(6)),
                                                  calendar: calendar).count, 4, "by day, not by hour")
    }

    /// Delivered pushes count; taken back, dropped, debug or untyped ones do not.
    func testNearbyTypesCountOnlyStandingPushes() {
        var delivered = entry("a", night: 5, type: "order")
        delivered.deliveredAt = night(5)
        var removed = entry("b", night: 7, type: "sound")
        removed.removedReason = .replaced
        removed.removedAt = night(1)
        var dropped = entry("c", night: 8, type: "route")
        dropped.notDeliveredReason = "notificationsOff"
        var debug = entry("d", night: 4, type: "zoom")
        debug.isDebug = true
        let legacy = entry("e", night: 7, type: nil)
        let entries = [delivered, removed, dropped, debug, legacy]
        XCTAssertEqual(QuestionPicker.nearbyTypes(entries, around: night(6), calendar: calendar), ["order"])
    }

    func testNearbyTypesTakeTheEarliestPushOfANight() {
        var later = entry("b", night: 7, type: "sound")
        later.scheduledFor = night(7).addingTimeInterval(600)
        let entries = [later, entry("a", night: 7, type: "order")]
        XCTAssertEqual(QuestionPicker.nearbyTypes(entries, around: night(6), calendar: calendar), ["order"])
    }
}
