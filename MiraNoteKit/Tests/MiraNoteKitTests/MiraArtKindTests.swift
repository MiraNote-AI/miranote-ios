import XCTest
@testable import MiraNoteKit

/// Records the kind each generate call carries.
actor KindRecordingStudio: ImageStudioService {
    private(set) var kinds: [GeneratedImageKind] = []

    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        kinds.append(kind)
        return [Data("img-A".utf8), Data("img-B".utf8)]
    }
    func cutout(image: Data, target: String?) async throws -> Data { Data("cut".utf8) }
    func stylize(image: Data, instruction: String) async throws -> Data { Data("styled".utf8) }
    func outline(image: Data) async throws -> Data { Data("outlined".utf8) }
    func describe(image: Data) async throws -> String { "a recorded look" }
}

@MainActor
final class MiraArtKindTests: XCTestCase {
    func testPictureGenerationRequestsArt() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.generateImage(prompt: "draw a paper crane", sticker: false)
        _ = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        let kinds = await studio.kinds
        XCTAssertEqual(kinds, [.art], "object art must not ride the background command")
    }

    func testStickerGenerationStillRequestsSticker() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.generateImage(prompt: "a cat sticker", sticker: true)
        _ = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        let kinds = await studio.kinds
        XCTAssertEqual(kinds, [.sticker])
    }

    func testBackgroundAskStillRequestsBackground() async throws {
        let studio = KindRecordingStudio()
        let intent = MiraIntent.setBackground(prompt: "a sunset background")
        _ = try await intent.perform(
            text: ScriptedText(), chat: ScriptedChat(), sessionID: nil, imageStudio: studio)
        let kinds = await studio.kinds
        XCTAssertEqual(kinds, [.background])
    }
}
