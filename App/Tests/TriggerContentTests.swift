import MiraNoteKit
import XCTest
@testable import MiraNote

/// The trigger's content words are Chinese whatever the app language
/// (handoff 7.0): every content key resolves in the built zh-Hans table,
/// with the format arguments the Kit fills in.
final class TriggerContentTests: XCTestCase {
    func testEveryContentKeyResolvesToChinese() {
        for key in TriggerContentKey.all {
            let value = TriggerContent.zh(key)
            XCTAssertNotEqual(value, key, "\(key) has no zh-Hans entry in the built app")
            XCTAssertTrue(value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, key)
            XCTAssertEqual(value.components(separatedBy: "%").count, key.components(separatedBy: "%").count, key)
        }
    }

    /// Whatever language the app is set to, the content stays Chinese.
    func testContentIgnoresTheAppLanguage() {
        let settings = AppSettings.shared
        let before = settings.language
        defer { settings.language = before }
        settings.language = .english
        let english = TriggerContent.zh(TriggerContentKey.keepThis)
        settings.language = .simplifiedChinese
        XCTAssertEqual(TriggerContent.zh(TriggerContentKey.keepThis), english)
        XCTAssertNotEqual(english, TriggerContentKey.keepThis)
    }
}
