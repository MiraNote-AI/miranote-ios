import XCTest

/// C10: the photo trigger never clears the whole notification center, only
/// its own `pt.` identifiers.
final class NotificationSafetyTests: XCTestCase {
    func testNoSourceRemovesAllNotifications() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["App/Sources", "MiraNoteKit/Sources"].map { root.appendingPathComponent($0) }
        let banned = ["removeAllPendingNotificationRequests", "removeAllDeliveredNotifications"]
        var scanned = 0
        var hits: [String] = []
        for folder in folders {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                scanned += 1
                let text = try String(contentsOf: file, encoding: .utf8)
                hits += banned.filter { text.contains($0) }.map { "\(file.lastPathComponent): \($0)" }
            }
        }
        XCTAssertGreaterThan(scanned, 100, "the source folders were found")
        XCTAssertEqual(hits, [])
    }
}
