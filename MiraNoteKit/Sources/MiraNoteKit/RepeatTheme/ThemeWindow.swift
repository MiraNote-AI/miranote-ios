import Foundation

/// The time window the repeat-theme finder looks at (decision 5): it starts
/// 120 days before the feature's first run and only grows forward from
/// there. It also remembers the feature print revision the stored records
/// are on (A1): prints of two revisions cannot be compared.
public struct ThemeWindow: Codable, Equatable, Sendable {
    /// Days looked back on the first run.
    public static let lookBackDays = 120

    /// The start of the local day 120 days before the first run.
    public let start: Date
    /// The print revision of the records; nil until a photo has been read.
    public var printRevision: Int?

    public init(start: Date, printRevision: Int?) {
        self.start = start
        self.printRevision = printRevision
    }

    /// The window of a first run at `now`.
    public static func first(now: Date, calendar: Calendar) -> ThemeWindow {
        let back = calendar.date(byAdding: .day, value: -lookBackDays, to: now)
            ?? now.addingTimeInterval(-Double(lookBackDays) * 86_400)
        return ThemeWindow(start: calendar.startOfDay(for: back), printRevision: nil)
    }
}

/// `themes/window.json`. A file that does not decode is set aside and the
/// window starts again from the next run (it costs one fresh look back).
public struct ThemeWindowStore: Sendable {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("window.json")
    }

    public func load() -> ThemeWindow? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        if let data = try? Data(contentsOf: file), let window = try? Self.decoder.decode(ThemeWindow.self, from: data) {
            return window
        }
        PhotoTriggerPaths.setAside(file)
        return nil
    }

    public func save(_ window: ThemeWindow) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(window).write(to: file, options: .atomic)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
