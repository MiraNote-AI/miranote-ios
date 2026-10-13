import XCTest
@testable import MiraNote

/// The graduation rule behind every first-run hint, including the tools
/// onboarding: shown until graduated, then never again.
final class HintCenterTests: XCTestCase {
    private let key = "miranote.graduatedHints"
    private var saved: [String]?

    override func setUp() {
        saved = UserDefaults.standard.stringArray(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: key)
    }

    func testAHintShowsUntilItGraduates() {
        XCTAssertTrue(HintCenter.shouldShow(ToolsOnboarding.hintID))
        HintCenter.graduate(ToolsOnboarding.hintID)
        XCTAssertFalse(HintCenter.shouldShow(ToolsOnboarding.hintID))
    }

    func testGraduatingOneHintLeavesTheOthers() {
        HintCenter.graduate(ToolsOnboarding.hintID)
        XCTAssertTrue(HintCenter.shouldShow("gesture-basics"))
    }
}
