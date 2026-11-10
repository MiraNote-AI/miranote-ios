import XCTest
@testable import MiraNoteKit

/// The scheduler picking each night's question by type (handoff refine 4.3,
/// acceptance R4).
final class PushSchedulerQuestionTests: PushSchedulerTestCase {
    private typealias Question = TriggerMemory.Ending.Question

    private func candidates(_ types: [String]) -> [Question] {
        types.map { Question(text: "Q \($0)", type: $0, source: "llm") }
    }

    /// No two nights within two of each other ask the same type (`other`
    /// aside), across the seven nights.
    private func assertNoTypeRepeatsNearby(file: StaticString = #filePath, line: UInt = #line) {
        let types = active.map { $0.questionType ?? "" }
        XCTAssertEqual(types.count, 7, file: file, line: line)
        for (index, type) in types.enumerated() where type != QuestionPicker.otherType {
            for other in index + 1..<min(types.count, index + 1 + QuestionPicker.reach) {
                XCTAssertNotEqual(types[other], type, "nights \(index) and \(other): \(types)", file: file, line: line)
            }
        }
    }

    /// Seven groups answered in one poll, all with the same candidates:
    /// each pick sees the ones before it, so the questions take turns.
    func testSevenAnsweredTogetherTakeTurns() async throws {
        client.questions = candidates(["zoom", "order", "found"])
        await makeScheduler().appBecameActive()
        XCTAssertEqual(client.pollManyCount, 1, "every night answered in the same poll")
        XCTAssertEqual(active.map { $0.questionType ?? "" },
                       ["zoom", "order", "found", "zoom", "order", "found", "zoom"])
        assertNoTypeRepeatsNearby()
        XCTAssertEqual(log.runs().first?.questionClashes, [])
        // The push's own ending asks the pick and keeps the other candidates.
        let second = try XCTUnwrap(records.load(active[1].pushId)?.memory.ending)
        XCTAssertEqual(second.question, "Q order")
        XCTAssertEqual(second.questionType, "order")
        XCTAssertEqual(second.questionSource, "llm")
        XCTAssertEqual(second.otherQuestions.map(\.type), ["zoom", "found"])
        XCTAssertEqual(active[1].question, "Q order")
    }

    /// Answers arriving out of night order: a later pick still keeps off
    /// the nights already fixed on both sides.
    func testOutOfOrderAnswersStillTakeTurns() async throws {
        client.questions = candidates(["zoom", "order", "found"])
        client.scripts[day("g0")] = [.running, .ok]
        client.scripts[day("g3")] = [.running, .running, .ok]
        await makeScheduler().appBecameActive()
        assertNoTypeRepeatsNearby()
    }

    /// Two candidates cannot cover five nights in a row: a night whose
    /// every candidate clashes asks the first, and the run log says so.
    func testClashTakesTheFirstAndIsLogged() async throws {
        client.questions = candidates(["sound", "route"])
        await makeScheduler().appBecameActive()
        let types = active.map { $0.questionType ?? "" }
        XCTAssertEqual(Array(types.prefix(2)), ["sound", "route"])
        let clashes = try XCTUnwrap(log.runs().first?.questionClashes)
        XCTAssertFalse(clashes.isEmpty)
        let slots = PushSlots.make(now: start, calendar: zone.calendar).map {
            SchedulePlanner.day($0, calendar: zone.calendar)
        }
        XCTAssertEqual(clashes.first?.slotDay, slots[2])
        XCTAssertEqual(clashes.first?.types, ["sound", "route"])
        XCTAssertEqual(clashes.first?.nearby, ["sound", "route"])
        XCTAssertEqual(types[2], "sound", "all clash: the first")
        XCTAssertTrue(LedgerText.copy(entries: ledger.load(), runs: log.runs(), counters: log.counters())
            .contains("question types taken nearby: \(slots[2]) sound/route"))
    }

    /// What is sent: the types fixed around the night the group may take;
    /// nothing fixed yet on the first run, so an empty list.
    func testMetaCarriesTheTypesAroundItsNight() async throws {
        client.questions = candidates(["zoom", "order", "found"])
        let scheduler = makeScheduler()
        await scheduler.appBecameActive()
        XCTAssertEqual(client.metas.count, 7)
        XCTAssertTrue(client.metas.allSatisfy { $0.recentQuestionTypes.isEmpty })
        let around = active.map { $0.questionType ?? "" }
        addBest()
        clock.advance(3600)
        await scheduler.appBecameActive()
        let meta = try XCTUnwrap(client.metas.last)
        XCTAssertEqual(meta.date, day("n"))
        XCTAssertEqual(meta.recentQuestionTypes, [around[1], around[2]], "tonight: the two nights after it")
        XCTAssertEqual(active.first?.belongsTo, day("n"))
        XCTAssertEqual(active.first?.questionType, "zoom", "order and found were taken next to it")
        assertNoTypeRepeatsNearby()
    }
}
