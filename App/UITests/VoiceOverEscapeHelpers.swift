import notify
import XCTest

/// VoiceOver's two-finger escape, which XCUITest cannot perform. The app's
/// -UITEST probe (`EscapeProbe`) offers the escape to the element named, as
/// UIKit does -- the element, then each container and view above it --
/// and the canvas probe's "escape" says which one took it. A model of
/// VoiceOver's walk: a device check with VoiceOver on is still the proof.
extension XCUIApplication {
    /// Escapes from the element with this identifier (one of the probe's
    /// `EscapeProbe.targets`) and returns the probe's record of it.
    @discardableResult
    func voiceOverEscape(from identifier: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let before = escapeRecord()
        notify_post("ai.miranote.uitest.escape." + identifier)
        // The probe refreshes every 0.25 s.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let record = escapeRecord()
            if record != before, record.contains(identifier) { return record }
            usleep(150_000)
        }
        XCTFail("the escape probe never answered for \(identifier)", file: file, line: line)
        return ""
    }

    /// The canvas probe's record of the last escape.
    func escapeRecord() -> String {
        let probe = descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
        guard probe.waitForExistence(timeout: 5),
              let state = try? JSONSerialization.jsonObject(with: Data(probe.label.utf8)) as? [String: Any]
        else { return "" }
        return state["escape"] as? String ?? ""
    }
}
