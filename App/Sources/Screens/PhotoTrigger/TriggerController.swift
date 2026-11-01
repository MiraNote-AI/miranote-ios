import MiraNoteKit
import SwiftUI

/// The photo trigger as the app holds it for its lifetime: one
/// `TriggerRun` (so "push next" remembers where it was until a relaunch),
/// the steps of the current press for the debug entry, the fake-AI switch,
/// and where pushes and photos are read back from.
@MainActor
@Observable
final class TriggerController {
    /// The current press's steps, oldest first.
    private(set) var steps: [TriggerProgress] = []
    private(set) var isRunning = false
    var fakeAI: Bool {
        didSet { AppSettings.storeDefaults.set(fakeAI, forKey: Self.fakeAIKey) }
    }

    let photos: TriggerPhotoProviding
    let records: PushRecordStore
    @ObservationIgnored private let run: TriggerRun
    @ObservationIgnored private let fakeAIFlag = FakeAIFlag()

    static let fakeAIKey = "photoTrigger.fakeAI"

    init(photos: TriggerPhotoProviding, library: PhotoLibraryReading, analyzer: PhotoAnalyzing, places: PlaceNaming,
         client: ComposeClient, notifier: TriggerNotifying, analyses: AnalysisStore, records: PushRecordStore,
         fakeAI: Bool) {
        self.photos = photos
        self.records = records
        self.fakeAI = fakeAI
        let flag = fakeAIFlag
        flag.value = fakeAI
        run = TriggerRun(TriggerDependencies(
            library: library, analyzer: analyzer, places: places, client: client, notifier: notifier,
            analyses: analyses, records: records, fakeAI: { flag.value }, zh: TriggerContent.zh,
            groupingReport: Self.saveGroupingReport
        ))
        Task { [weak self, run] in
            for await step in await run.progress() {
                self?.record(step)
            }
        }
    }

    private func record(_ step: TriggerProgress) {
        if step == .preparing { steps = [] }
        // One counting line, not one per photo.
        if case .analyzing = step, case .analyzing = steps.last {
            steps[steps.count - 1] = step
        } else {
            steps.append(step)
        }
    }

    /// "Push one in 10 s" (`next` false) or "push the next group".
    func push(next: Bool) {
        guard !isRunning else { return }
        isRunning = true
        fakeAIFlag.value = fakeAI
        Task {
            if next { await run.pushNext() } else { await run.pushTop() }
            isRunning = false
        }
    }

    /// Keeps the last press's grouping on the phone (local only) for checking.
    @Sendable nonisolated static func saveGroupingReport(_ data: Data) {
        let file = GroupingReport.defaultFile
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The app's one controller: PhotoKit, Vision, Apple's geocoder and the
    /// photo-collections backend -- or, under `-UITEST-TRIGGER`, the
    /// synthetic library and a scripted backend.
    static func make() -> TriggerController {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST-TRIGGER") {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestTrigger", isDirectory: true)
            if !arguments.contains("-KEEP_SETTINGS") { try? FileManager.default.removeItem(at: folder) }
            let synthetic = SyntheticTriggerLibrary()
            return TriggerController(
                photos: synthetic, library: synthetic, analyzer: synthetic, places: UITestPlaces(),
                client: UITestComposeClient(), notifier: UITestNotifier(),
                analyses: AnalysisStore(directory: folder.appendingPathComponent("analysis")),
                records: PushRecordStore(directory: folder.appendingPathComponent("pushes")),
                fakeAI: arguments.contains("-TRIGGER-FAKE-AI")
            )
        }
        #endif
        let reader = PhotoLibraryReader()
        return TriggerController(
            photos: reader, library: reader, analyzer: PhotoAnalyzer(photos: reader), places: PlaceNamer(),
            client: LiveComposeClient(), notifier: LiveTriggerNotifier(photos: reader),
            analyses: AnalysisStore(directory: AnalysisStore.defaultDirectory),
            records: PushRecordStore(directory: PushRecordStore.defaultDirectory),
            fakeAI: AppSettings.storeDefaults.bool(forKey: fakeAIKey)
        )
    }
}

/// The switch as the run reads it, off the main actor.
private final class FakeAIFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The trigger's content words (push, question, button, bucket) are
/// Chinese whatever the app language (handoff 7.0): read from the built
/// zh-Hans table, falling back to the key.
enum TriggerContent {
    private static let table: Bundle? = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init)

    @Sendable static func zh(_ key: String) -> String {
        table?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }
}
