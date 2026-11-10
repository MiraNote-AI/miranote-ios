import Foundation

/// Test fixture files next to this one, read by path so the package needs no
/// resource bundle.
enum Fixtures {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(name)
    }
}
