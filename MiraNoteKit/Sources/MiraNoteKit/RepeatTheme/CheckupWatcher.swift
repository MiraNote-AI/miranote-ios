import Foundation

/// Watches the checkups of one run: how many, the print revision they
/// came with, and which photos gave no theme vision.
final class CheckupWatcher: PhotoAnalyzing, @unchecked Sendable {
    private let base: PhotoAnalyzing
    private let lock = NSLock()
    private var checkups = 0
    private var lastRevision: Int?
    private var withoutVision = Set<String>()

    init(base: PhotoAnalyzing) {
        self.base = base
    }

    var count: Int { lock.withLock { checkups } }
    /// The revision of the latest checkup that had vision.
    var revision: Int? { lock.withLock { lastRevision } }
    var noVision: Set<String> { lock.withLock { withoutVision } }

    func analyze(_ id: String) async -> PhotoAnalysis? {
        await base.analyze(id)
    }

    func checkup(_ id: String) async -> (analysis: PhotoAnalysis, theme: ThemeVision?)? {
        let checked = await base.checkup(id)
        lock.withLock {
            checkups += 1
            if let checked {
                if let theme = checked.theme { lastRevision = theme.printRevision } else { withoutVision.insert(id) }
            }
        }
        return checked
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? {
        base.distance(first, second)
    }
}
