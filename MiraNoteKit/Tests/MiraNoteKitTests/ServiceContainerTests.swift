import XCTest
@testable import MiraNoteKit

final class ServiceContainerTests: XCTestCase {
    func testLiveContainerWiresTheLiveTextService() {
        XCTAssertTrue(ServiceContainer.live.textTransform is LiveTextTransformService,
                      "the running app must use the live text service, not the mock")
    }

    func testLiveContainerWiresTheLiveVoiceService() {
        XCTAssertTrue(ServiceContainer.live.voiceTranscription is LiveVoiceTranscriptionService,
                      "the running app must use the live voice service, not the mock")
    }

    func testLiveContainerWiresTheLiveChatService() {
        XCTAssertTrue(ServiceContainer.live.chat is LiveChatService,
                      "the running app must use the live chat service, not the mock")
    }

    func testMockContainerWiresMockServices() {
        XCTAssertTrue(ServiceContainer.mock.textTransform is MockTextTransformService)
        XCTAssertTrue(ServiceContainer.mock.voiceTranscription is MockVoiceTranscriptionService)
        XCTAssertTrue(ServiceContainer.mock.chat is MockChatService)
    }
}
