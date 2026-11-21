import Foundation

/// How far one checkup pass got.
struct CheckupOutcome: Sendable {
    /// The analyses this pass made and saved (the photos `needsV1` asked
    /// for); results saved by earlier runs are not repeated here.
    let analyses: [String: PhotoAnalysis]
    /// The capture date of the oldest photo such that it and every newer
    /// one is done (read now or before, or waiting on a retry); nil when
    /// not even the newest is.
    let checkedThrough: Date?
    /// Every photo is done: the pass was not cut short by its deadline.
    let finished: Bool
}

/// The one pass over the library that both trigger modes share: each photo
/// is read once (`PhotoAnalyzing.checkup`), newest first, and that one read
/// fills V1's analysis and the repeat-theme record. Results are saved as
/// they come, so a pass stopped by its deadline (or killed) resumes where
/// it left off. A photo that fails is written down and left alone for a
/// day.
struct PhotoCheckupRunner {
    /// A photo whose analysis failed is tried again this long after.
    static let retryAfter: TimeInterval = 86_400
    /// Failures are written down every this many, so a run killed midway
    /// still remembers most of them.
    static let failuresBatch = 20
    /// Theme records are written down every this many: each write rewrites
    /// the month it lands in, so a first checkup of thousands of photos
    /// writes in larger steps (a killed run reads at most these again).
    static let themeBatch = 100

    // swiftlint:disable function_parameter_count
    /// Checks up every photo of `assets` that `needsV1` or `needsTheme`
    /// asks for and that is not waiting on a retry, newest first, until
    /// `clock` reaches `deadline` (nil: no limit). `now` is the run's time
    /// for failure bookkeeping and the theme filter.
    static func run(_ assets: [LibraryAsset], needsV1: (String) -> Bool, needsTheme: (String) -> Bool,
                    analyzer: PhotoAnalyzing, analyses store: AnalysisStore, themes: ThemePhotoStore?,
                    now: Date, calendar: Calendar, deadline: Date?, clock: () -> Date = { Date() },
                    report: (TriggerProgress) async -> Void) async -> CheckupOutcome {
        let ordered = assets.sorted { ($0.takenAt ?? .distantPast, $0.id) > ($1.takenAt ?? .distantPast, $1.id) }
        var pass = Pass(store: store, themes: themes, calendar: calendar, now: now)
        let due = ordered.filter {
            (needsV1($0.id) || (themes != nil && needsTheme($0.id))) && !pass.isWaiting($0.id)
        }
        let todo = Set(due.map(\.id))
        var done = assets.count - due.count
        await report(.analyzing(done: done, total: assets.count))

        var checkedThrough: Date?
        var finished = true
        for asset in ordered {
            if todo.contains(asset.id) {
                if let deadline, clock() >= deadline {
                    finished = false
                    break
                }
                let checked = await analyzer.checkup(asset.id)
                pass.take(asset, checked, v1: needsV1(asset.id), theme: themes != nil && needsTheme(asset.id))
                done += 1
                await report(.analyzing(done: done, total: assets.count))
            }
            if let takenAt = asset.takenAt { checkedThrough = takenAt }
        }
        pass.flush(all: true)
        return CheckupOutcome(analyses: pass.results, checkedThrough: checkedThrough, finished: finished)
    }
    // swiftlint:enable function_parameter_count

    /// What one pass has read and not all written down yet.
    private struct Pass {
        let store: AnalysisStore
        let themes: ThemePhotoStore?
        let calendar: Calendar
        let now: Date
        var failures: [String: Date]
        var results: [String: PhotoAnalysis] = [:]
        /// Theme records not yet written.
        var pending: [ThemePhoto] = []
        /// Where the stored theme records are: read at the pass's first
        /// write, then kept up to date by its writes.
        var index: ThemePhotoStore.MonthIndex?
        /// Failure changes not yet written.
        var unsaved = 0

        init(store: AnalysisStore, themes: ThemePhotoStore?, calendar: Calendar, now: Date) {
            self.store = store
            self.themes = themes
            self.calendar = calendar
            self.now = now
            failures = store.failures()
        }

        /// Failed less than `retryAfter` ago: left alone this run.
        func isWaiting(_ id: String) -> Bool {
            guard let failed = failures[id] else { return false }
            return (0..<retryAfter).contains(now.timeIntervalSince(failed))
        }

        /// Keeps one checkup's answer: V1's analysis saved at once, the
        /// theme record batched; nil is a failure.
        mutating func take(_ asset: LibraryAsset, _ checked: (analysis: PhotoAnalysis, theme: ThemeVision?)?,
                           v1: Bool, theme: Bool) {
            if let checked {
                if v1 {
                    // The file name goes with it: later runs need not ask PhotoKit.
                    let named = checked.analysis.with(originalFilename: asset.originalFilename)
                    try? store.save(named)
                    results[asset.id] = named
                }
                if theme, let vision = checked.theme,
                   let photo = PhotoCheckupRunner.themePhoto(asset, analysis: checked.analysis, vision: vision,
                                                             now: now) {
                    pending.append(photo)
                }
                if failures.removeValue(forKey: asset.id) != nil { unsaved += 1 }
            } else {
                failures[asset.id] = now
                unsaved += 1
            }
            flush()
        }

        /// Writes the failures down once `failuresBatch` have gathered, the
        /// theme records once `themeBatch` have; `all`: whatever is left.
        mutating func flush(all: Bool = false) {
            if unsaved >= (all ? 1 : failuresBatch) {
                try? store.saveFailures(failures)
                unsaved = 0
            }
            if let themes, pending.count >= (all ? 1 : themeBatch) {
                var known = index ?? themes.monthIndex()
                try? themes.upsert(pending, calendar: calendar, index: &known)
                index = known
                pending = []
            }
        }
    }

    /// The theme record of one read photo; nil without a capture date.
    private static func themePhoto(_ asset: LibraryAsset, analysis: PhotoAnalysis, vision: ThemeVision,
                                   now: Date) -> ThemePhoto? {
        guard let takenAt = asset.takenAt else { return nil }
        let isTheme = LibraryFilter.eligible(asset, now: now) && !analysis.isUtility
            && !analysis.broad.contains(.document)
        return ThemePhoto(id: asset.id, takenAt: takenAt, location: asset.location, labels: vision.labels,
                          aesthetics: analysis.aesthetics, faces: analysis.faces, isTheme: isTheme,
                          print: ThemePhoto.normalized(vision.print), printRevision: vision.printRevision)
    }
}
