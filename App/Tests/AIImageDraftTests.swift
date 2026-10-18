import MiraNoteKit
import XCTest
@testable import MiraNote

/// The Image tool's AI Image draft: words in, candidates out; Cancel drops
/// a painting for good, and a result never lands twice or after a Cancel.
@MainActor
final class AIImageDraftTests: XCTestCase {
    private let studio = GatedStudio()
    private let one = Data([1])
    private let two = Data([2])

    override func tearDown() {
        studio.releaseAll()
        super.tearDown()
    }

    func testGenerateShowsTheCandidatesAndTakeHandsOneOver() async {
        let draft = AIImageDraft()
        draft.prompt = "  a lighthouse  "
        draft.generate(with: studio)
        XCTAssertTrue(draft.generating)
        XCTAssertTrue(draft.holdsWork, "a painting on its way is work")
        XCTAssertFalse(draft.canGenerate, "one painting at a time")

        studio.generateCalls.releaseNext(.success([one, two]))
        let arrived = await eventually { !draft.generating }
        XCTAssertTrue(arrived)
        XCTAssertEqual(draft.candidates, [one, two])
        XCTAssertTrue(draft.holdsWork, "candidates waiting are work")

        var placed: [(Data, String)] = []
        XCTAssertTrue(draft.pick(1) { placed.append(($0, $1)); return true })
        XCTAssertEqual(placed.count, 1)
        XCTAssertEqual(placed.first?.0, two)
        XCTAssertEqual(placed.first?.1, "a lighthouse", "the words name the picture")
        XCTAssertTrue(draft.candidates.isEmpty)
        XCTAssertFalse(draft.holdsWork)
        XCTAssertFalse(draft.pick(0) { _, _ in true }, "a pick lands once")
    }

    func testAPickThatCannotBeStoredKeepsTheCandidates() async {
        let draft = AIImageDraft()
        draft.prompt = "a lighthouse"
        draft.generate(with: studio)
        studio.generateCalls.releaseNext(.success([one, two]))
        let arrived = await eventually { !draft.candidates.isEmpty }
        XCTAssertTrue(arrived)
        XCTAssertFalse(draft.pick(0) { _, _ in false })
        XCTAssertEqual(draft.candidates, [one, two], "still there to try again")
        XCTAssertNotNil(draft.notice)
    }

    func testDiscardDropsARunningPaintingForGood() async {
        let draft = AIImageDraft()
        draft.prompt = "a lighthouse"
        draft.generate(with: studio)
        draft.discard()
        XCTAssertFalse(draft.generating)
        XCTAssertFalse(draft.holdsWork)

        studio.generateCalls.releaseNext(.success([one, two]))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(draft.candidates.isEmpty, "a cancelled painting never shows up")
        XCTAssertFalse(draft.generating)
    }

    func testANewGenerationIsNotOverwrittenByACancelledOne() async {
        let draft = AIImageDraft()
        draft.prompt = "a lighthouse"
        draft.generate(with: studio)
        draft.discard()
        draft.generate(with: studio)

        studio.generateCalls.release(1, .success([two]))
        let arrived = await eventually { !draft.candidates.isEmpty }
        XCTAssertTrue(arrived)
        studio.generateCalls.release(0, .success([one]))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(draft.candidates, [two], "the cancelled call's result stays out")
    }

    func testAFailureSaysSoAndKeepsTheWords() async {
        let draft = AIImageDraft()
        draft.prompt = "a lighthouse"
        draft.generate(with: studio)
        studio.generateCalls.releaseNext(.failure(GateError()))
        let settled = await eventually { !draft.generating }
        XCTAssertTrue(settled)
        XCTAssertNotNil(draft.notice)
        XCTAssertTrue(draft.candidates.isEmpty)
        XCTAssertEqual(draft.prompt, "a lighthouse", "the words stay for another try")
        XCTAssertTrue(draft.canGenerate)
    }

    func testBlankWordsGenerateNothing() {
        let draft = AIImageDraft()
        draft.prompt = "   "
        XCTAssertFalse(draft.canGenerate)
        draft.generate(with: studio)
        XCTAssertFalse(draft.generating)
        XCTAssertEqual(studio.generateCalls.count, 0)
    }
}
