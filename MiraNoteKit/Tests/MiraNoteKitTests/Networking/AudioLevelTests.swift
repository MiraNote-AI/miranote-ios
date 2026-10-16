import XCTest
@testable import MiraNoteKit

/// The live meter under the recorder bar (handoff screen 08): average
/// power in decibels becomes a 0 ... 1 level, and the mock reports one only
/// while it records.
@MainActor
final class AudioLevelTests: XCTestCase {
    func testSilenceAndBelowTheFloorReadZero() {
        XCTAssertEqual(AudioLevel.normalized(power: -160), 0)
        XCTAssertEqual(AudioLevel.normalized(power: AudioLevel.floorDecibels), 0)
    }

    func testFullScaleReadsOneAndNeverMore() {
        XCTAssertEqual(AudioLevel.normalized(power: 0), 1)
        XCTAssertEqual(AudioLevel.normalized(power: 6), 1)
    }

    func testTheMeterIsLinearInDecibels() {
        XCTAssertEqual(AudioLevel.normalized(power: AudioLevel.floorDecibels / 2), 0.5, accuracy: 0.0001)
    }

    func testTheMockReportsItsLevelOnlyWhileRecording() async throws {
        let recorder = MockAudioRecorder(recordingLevel: 0.7)
        XCTAssertEqual(recorder.level, 0)
        try await recorder.start()
        XCTAssertEqual(recorder.level, 0.7)
        recorder.recordingLevel = 0.2
        XCTAssertEqual(recorder.level, 0.2)
        _ = try await recorder.stop()
        XCTAssertEqual(recorder.level, 0)
    }
}
