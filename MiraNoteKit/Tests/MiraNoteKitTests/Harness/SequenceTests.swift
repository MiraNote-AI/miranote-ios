import XCTest
@testable import MiraNoteKit

/// The random-sequence runs (see SequenceHarness.swift for the knobs). A
/// failure prints its seed and a shortened sequence: keep that as a named
/// regression test next to the code it broke.
@MainActor
final class SequenceTests: XCTestCase {
    func testCanvasSequencesKeepTheirInvariants() async {
        await SequenceHarness.run(CanvasSequenceModel.self)
    }

    func testChatStagingSequencesKeepTheirInvariants() async {
        await SequenceHarness.run(ChatStagingModel.self)
    }

    func testChatVoiceSequencesKeepTheirInvariants() async {
        await SequenceHarness.run(ChatVoiceModel.self, .fromEnvironment(sequences: 500, length: 20))
    }
}
