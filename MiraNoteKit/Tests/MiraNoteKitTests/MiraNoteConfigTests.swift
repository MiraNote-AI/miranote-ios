import XCTest
@testable import MiraNoteKit

final class MiraNoteConfigTests: XCTestCase {
    func testBackendBaseURLsTargetLocalhostPOCs() {
        XCTAssertEqual(MiraNoteConfig.Backend.textBaseURL.absoluteString, "http://localhost:8001")
        XCTAssertEqual(MiraNoteConfig.Backend.voiceBaseURL.absoluteString, "http://localhost:8005")
    }
}
