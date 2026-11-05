import MiraNoteKit
import SwiftUI

/// The interactive editor. The canvas is home base: Background, Voice and
/// Text act directly on it, Image and Sticker open their panel scenes, and
/// Done composes the memory (title from its most prominent text) and files it.
struct EditorFlowView: View {
    var onExit: () -> Void = {}
    var onComplete: (Memory) -> Void = { _ in }
    /// Files the page quietly WITHOUT leaving the editor -- the autosave
    /// half of "editing autosaves, so Done never says Save".
    var onAutosave: (Memory) -> Void = { _ in }
    var recorderFactory: @MainActor () -> AudioRecording = { AudioRecorder() }
    var services: ServiceContainer = .mock
    /// Set only for a page drafted from a push: it is filed only once the
    /// writer touched it (or tapped Done), and `onMadePage` tells the ledger.
    var pushId: String?
    var onMadePage: (String) -> Void = { _ in }
    /// A push draft left as it arrived: nothing of it is filed.
    var onDiscardDraft: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: CanvasViewModel
    /// The page was filed while the app was away: from then on leaving
    /// files it again, whatever it holds.
    @State private var autosaved = false
    @State private var mira: MiraCanvasCoordinator
    @State private var scene: FlowScene = .canvas
    @State private var pendingTool: EditorMode?
    /// Survives the panel-to-canvas hop: the Sticker panel fills it, the
    /// canvas empties it when the Add hop lands.
    @State private var pendingPlacement: PendingPlacement?
    /// The canvas's scroll, kept while the Sticker panel stands in for it.
    @State private var scrollMemory = CanvasScrollMemory()
    /// One photo editor per photo, beside `editor`: an AI edit kept running
    /// with Done outlives the canvas scene the Sticker scene replaces.
    @State private var photoEditors = PhotoEditors()

    /// Pass `memory` to edit an existing page; omitted, a fresh starter
    /// draft opens. `prompts`: text on it filed only once rewritten.
    init(
        memory: Memory? = nil,
        prompts: [CanvasItem.ID: String] = [:],
        onExit: @escaping () -> Void = {},
        onComplete: @escaping (Memory) -> Void = { _ in },
        onAutosave: @escaping (Memory) -> Void = { _ in },
        recorderFactory: @escaping @MainActor () -> AudioRecording = { AudioRecorder() },
        services: ServiceContainer = .mock,
        pushId: String? = nil,
        onMadePage: @escaping (String) -> Void = { _ in },
        onDiscardDraft: @escaping () -> Void = {}
    ) {
        self.pushId = pushId
        self.onMadePage = onMadePage
        self.onDiscardDraft = onDiscardDraft
        self.onExit = onExit
        self.onComplete = onComplete
        self.onAutosave = onAutosave
        self.recorderFactory = recorderFactory
        self.services = services
        // A fresh memory starts BLANK (v2.1); the Mira-generated draft is
        // the recorded D3 backend gap and takes over here when it lands.
        _editor = State(initialValue: CanvasViewModel(
            memory: memory?.materializedForEditing() ?? Memory(),
            prompts: prompts
        ))
        _mira = State(initialValue: MiraCanvasCoordinator(
            text: services.textTransform,
            chat: services.chat,
            imageStudio: services.imageStudio
        ))
    }

    var body: some View {
        content
            .id(scene)
            .transition(.opacity)
            .onChange(of: scenePhase) {
                // Autosave against app death: words survive a backgrounded
                // app being jettisoned. file() replaces by id, so the later
                // Done/Home filing never duplicates this one.
                // An untouched push draft is not worth keeping: nothing of the
                // writer's is lost by leaving it unsaved.
                if scenePhase == .background && !editor.isBlankPage && !isUntouchedPushDraft {
                    onAutosave(editor.composedMemory())
                    autosaved = true
                    if let pushId { onMadePage(pushId) }
                }
            }
    }

    /// Leaving keeps the words (autosave semantics): Done and Home both
    /// file a page with anything on it -- a background alone counts; only
    /// an untouched blank page keeps nothing -- no junk "New memory"
    /// entries in the journal.
    private func finish() {
        if editor.isBlankPage {
            onExit()
        } else {
            onComplete(editor.composedMemory())
            if let pushId { onMadePage(pushId) }
        }
    }

    /// A push draft as it arrived (`CanvasViewModel.isAsArrived`) and
    /// never filed.
    private var isUntouchedPushDraft: Bool {
        pushId != nil && !autosaved && editor.isAsArrived
    }

    /// Back: an untouched push draft leaves nothing behind; anything else
    /// is Done's filing.
    private func back() {
        if isUntouchedPushDraft {
            onDiscardDraft()
            onExit()
        } else {
            finish()
        }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .canvas:
            CanvasScene(
                editor: editor,
                mira: mira,
                imageStudio: services.imageStudio,
                actions: actions(back: back, done: finish),
                pendingTool: $pendingTool,
                pendingPlacement: $pendingPlacement,
                scrollMemory: scrollMemory,
                photoEditors: $photoEditors,
                recorderFactory: recorderFactory,
                transcription: services.voiceTranscription
            )
        case .sticker:
            StickerPanelScene(
                editor: editor,
                studio: services.imageStudio,
                actions: actions(back: { navigate(.canvas) }, done: { navigate(.canvas) }),
                pendingPlacement: $pendingPlacement,
                scrollMemory: scrollMemory
            )
        case .home, .imageStart, .chat, .collection, .note, .export:
            // Export left the main flow in v2.1 (share/export moves to
            // reading mode in Phase E); the scene stays catalog-only.
            EmptyView()
        }
    }

    private func actions(
        onGo: (() -> Void)? = nil,
        back: (() -> Void)? = nil,
        done: (() -> Void)? = nil
    ) -> EditorActions {
        EditorActions(
            selectMode: { select(mode: $0) },
            go: onGo ?? { navigate(.canvas) },
            leading: back ?? { navigate(.canvas) },
            done: done ?? { navigate(.canvas) }
        )
    }

    /// Background, Voice, Text and Image always act on the canvas; from the
    /// Sticker panel they carry over as a pending tool the canvas consumes
    /// on arrival.
    private func select(mode: EditorMode) {
        switch mode {
        case .sticker:
            navigate(.sticker)
        case .background, .voice, .text, .image:
            pendingTool = mode
            navigate(.canvas)
        }
    }

    private func navigate(_ next: FlowScene) {
        withAnimation(.easeInOut(duration: 0.22)) { scene = next }
    }
}

/// Home and everything it opens. Collections are real and persisted: tapping a
/// card pushes its detail; "Start a memory" opens the editor and files the
/// finished note; the quick-capture field opens the MiraNote AI chat, which can
/// turn the conversation into a filed memory.
struct HomeFlow: View {
    @Environment(\.services) private var services
    @State private var viewModel = HomeViewModel(store: HomeFlow.makeStore())
    @State private var route: Route?
    @State private var path = NavigationPath()
    @State private var settings = AppSettings.shared
    @State private var profile = LocalProfile(defaults: AppSettings.storeDefaults, images: HomeFlow.profileImages)
    @State private var moodJudge: MoodJudge?

    /// Where a newly finished memory is filed by default.
    private static let inbox = "Daily Log"

    /// The photo trigger: its run, push records and library photos.
    /// One per launch (`shared`), however often HomeFlow is re-made.
    @State private var trigger = TriggerController.shared
    @State private var router = TriggerLaunchRouter.shared
    /// The debug entry and automatic scheduling: development and TestFlight
    /// builds (InstallSource).
    @State private var triggerGates = InstallSource.Gates.closed
    /// The ending's button turning its story into a canvas draft.
    @State private var keeper = TriggerKeep()

    /// A note addressed within its collection, for stack navigation.
    private struct NoteRef: Hashable {
        let collectionID: MemoryCollection.ID
        let noteID: Memory.ID
    }

    /// UI tests keep the avatar in a folder of their own, emptied at launch
    /// like the settings' suite (`AppSettings.storeDefaults`);
    /// `-KEEP_SETTINGS` keeps it (a test's own relaunch).
    private static let profileImages: ImageFileStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UITestProfile", isDirectory: true)
            if !ProcessInfo.processInfo.arguments.contains("-KEEP_SETTINGS") {
                try? FileManager.default.removeItem(at: folder)
            }
            return ImageFileStore(directory: folder)
        }
        #endif
        return LocalProfile.defaultImages
    }()

    /// UI tests drive Mira with scripted services so working, stop, and
    /// failure states are deterministic; otherwise the app's own container
    /// is used unchanged.
    private static func editorServices(base: ServiceContainer) -> ServiceContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            return .uiTestScripted
        }
        #endif
        return base
    }

    /// UI tests record with a canned in-memory recorder (no mic permission),
    /// at full level so the live bars draw the handoff's pattern. A mic that
    /// is slow to come up is `-MIC_START_DELAY <ms>`; `-TIME_TAKES` times
    /// each take; `-FAIL_LATER_MICS` fails every mic after the first.
    @MainActor private static func makeRecorder() -> AudioRecording {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            let delay = UserDefaults.standard.integer(forKey: "MIC_START_DELAY")
            let mock = MockAudioRecorder(recordingLevel: 1, startDelay: .milliseconds(delay))
            if ProcessInfo.processInfo.arguments.contains("-FAIL_LATER_MICS") { return UITestFailingRecorder(mock) }
            return ProcessInfo.processInfo.arguments.contains("-TIME_TAKES") ? UITestTimedRecorder(mock) : mock
        }
        #endif
        return AudioRecorder()
    }

    /// UI tests save to a stub Photos library (no permission prompt) that
    /// succeeds, or refuses under `-PHOTOS-DENIED`.
    private static func makePhotoSaver() -> PhotoSaver {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST") {
            let denied = arguments.contains("-PHOTOS-DENIED")
            return PhotoSaver { _ in !denied }
        }
        #endif
        return .library
    }

    private enum Route: Identifiable {
        case editor
        /// A blank page started from a journal's "+ New memory": filed there.
        case editorIn(journal: MemoryCollection.ID)
        case editMemory(Memory)
        case chat(String)
        /// A page Mira drafted in chat, opening in the editor as a new note;
        /// `prompts`: text on it filed only once rewritten (the trigger's question).
        case draft(Memory, prompts: [CanvasItem.ID: String] = [:], pushId: String? = nil)
        /// The photo trigger's story and ending, opened from a push.
        case trigger(TriggerOpening)

        var id: String {
            switch self {
            case .editor: return "editor"
            case .editorIn(let journal): return "editor-in-\(journal.uuidString)"
            case .editMemory(let memory): return "edit-\(memory.id.uuidString)"
            case .chat: return "chat"
            case .draft(let memory, _, _): return "draft-\(memory.id.uuidString)"
            case .trigger(let opening): return "trigger-\(opening.pushId)"
            }
        }

        /// The journal a new page is filed in, when it was started in one.
        var journal: MemoryCollection.ID? {
            if case .editorIn(let id) = self { return id }
            return nil
        }
    }

    /// Navigation token for the recently-deleted bin.
    struct TrashRoute: Hashable {}

    /// Navigation tokens for the Settings and Profile screens.
    enum AccountRoute: Hashable {
        case settings, appearance, language, profile
    }

    /// Navigation token for the star jar.
    struct StarJarRoute: Hashable {}

    /// Asks the moods of saved pages in the background (the star jar's
    /// colors); made on first use, then one queue for the whole app.
    private func judgeMoods(_ noteIDs: [Memory.ID]) {
        guard !noteIDs.isEmpty else { return }
        makeMoodJudge().judge(noteIDs)
    }

    /// The pages the star jar shows (`[]`: it closed): asked after saves.
    private func showMoods(_ noteIDs: [Memory.ID]) {
        if noteIDs.isEmpty { moodJudge?.show([]) } else { makeMoodJudge().show(noteIDs) }
    }

    private func makeMoodJudge() -> MoodJudge {
        let judge = moodJudge ?? MoodJudge(service: Self.editorServices(base: services).mood, library: viewModel)
        moodJudge = judge
        return judge
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                viewModel: viewModel,
                onStart: { route = .editor },
                onQuickCapture: { route = .chat($0) },
                onOpenCollection: { path.append($0) },
                onOpenTrash: { path.append(TrashRoute()) },
                onOpenStarJar: { path.append(StarJarRoute()) },
                onOpenSettings: { path.append(AccountRoute.settings) },
                onOpenProfile: { path.append(AccountRoute.profile) },
                triggerEntry: triggerGates.showsDebugEntry ? TriggerDebugEntry(controller: trigger) : nil
            )
            .navigationBarHidden(true)
            .navigationDestination(for: MemoryCollection.self) { collection in
                CollectionDetailView(
                    viewModel: viewModel,
                    collectionID: collection.id,
                    onBack: { path.removeLast() },
                    onOpenNote: { path.append(NoteRef(collectionID: collection.id, noteID: $0.id)) },
                    onNewMemory: { route = .editorIn(journal: collection.id) }
                )
                .navigationBarHidden(true)
            }
            .navigationDestination(for: NoteRef.self) { ref in
                if let memory = viewModel.note(ref.noteID, in: ref.collectionID) {
                    ReadingView(
                        memory: memory,
                        onBack: { path.removeLast() },
                        onEdit: { route = .editMemory(memory) },
                        photoSaver: Self.makePhotoSaver()
                    )
                    .navigationBarHidden(true)
                }
            }
            .navigationDestination(for: StarJarRoute.self) { _ in
                StarJarView(
                    viewModel: viewModel,
                    onBack: { path.removeLast() },
                    onOpenNote: { path.append(NoteRef(collectionID: $0.collectionID, noteID: $0.id)) },
                    onShow: showMoods
                )
                .navigationBarHidden(true)
            }
            .navigationDestination(for: TrashRoute.self) { _ in
                RecentlyDeletedView(
                    viewModel: viewModel,
                    onBack: { path.removeLast() }
                )
                .navigationBarHidden(true)
            }
            .navigationDestination(for: AccountRoute.self) { route in
                Group {
                    switch route {
                    case .settings:
                        SettingsView(
                            settings: settings,
                            onBack: { path.removeLast() },
                            onOpenAppearance: { path.append(AccountRoute.appearance) },
                            onOpenLanguage: { path.append(AccountRoute.language) }
                        )
                    case .appearance:
                        AppearanceView(settings: settings, onBack: { path.removeLast() })
                    case .language:
                        LanguageView(settings: settings, onBack: { path.removeLast() })
                    case .profile:
                        ProfileView(profile: profile, onBack: { path.removeLast() })
                    }
                }
                .navigationBarHidden(true)
            }
        }
        // The Appearance setting, applied live (a choice redraws at once).
        .environment(\.theme, Theme(appearance: settings.appearance))
        .task {
            guard Self.triggerEntryAllowed else { return }
            triggerGates = await trigger.resolveGates { await InstallSource.live() }
        }
        .triggerLifecycle(trigger, enabled: triggerGates.schedulesAutomatically)
        // A tapped push, also one that launched the app: open it once Home is
        // up and no other cover (an editor, chat, a story) is on screen.
        .task(id: PendingPushKey(pushId: router.pending, coverUp: route != nil || keeper.switching)) {
            await openPendingPush()
        }
        #if DEBUG
        .background { ChatPhotoFilesProbe() }
        .background { TriggerScheduleProbe(controller: trigger) }
        // Under a cover the scene's own probe shows too; nothing here listens.
        .background(DebugStateProbe { ["scene": "home", "listening": [String: Bool]()] })
        #endif
        .fullScreenCover(item: $route) { presented in
            switch presented {
            case .editor, .editorIn:
                let journal = presented.journal
                EditorFlowView(
                    onExit: { route = nil },
                    onComplete: { memory in
                        viewModel.file(memory, inCollection: journal, orTitled: Self.inbox)
                        judgeMoods([memory.id])
                        route = nil
                    },
                    onAutosave: { viewModel.file($0, inCollection: journal, orTitled: Self.inbox) },
                    recorderFactory: Self.makeRecorder,
                    services: Self.editorServices(base: services)
                )
                // The editor, its tools and Mira chat stay on System.
                .environment(\.theme, Theme(appearance: .system))
            case .editMemory(let memory), .draft(let memory, _, _):
                EditorFlowView(
                    memory: memory,
                    prompts: Self.prompts(of: presented),
                    onExit: { route = nil },
                    onComplete: { edited in
                        viewModel.file(edited, underCollectionTitled: Self.inbox)
                        judgeMoods([edited.id])
                        route = nil
                    },
                    onAutosave: { viewModel.file($0, underCollectionTitled: Self.inbox) },
                    recorderFactory: Self.makeRecorder,
                    services: Self.editorServices(base: services),
                    pushId: Self.pushId(of: presented),
                    onMadePage: { trigger.madePage($0) },
                    // The page as drafted: its photo copies are the draft's own.
                    onDiscardDraft: { TriggerDraftMaker.discard(memory) }
                )
                .environment(\.theme, Theme(appearance: .system))
            case .trigger(let opening):
                triggerStory(opening)
            case .chat(let seed):
                // Same swap as the editor: -UITEST talks to the scripted
                // chat so replies (and drafts) are deterministic.
                MiraChatView(
                    service: Self.editorServices(base: services).chat,
                    transcription: Self.editorServices(base: services).voiceTranscription,
                    studio: Self.editorServices(base: services).imageStudio,
                    recorderFactory: Self.makeRecorder,
                    seed: seed,
                    onExit: { route = nil },
                    onOpenCanvas: {
                        route = nil
                        // Swap covers only after this one is gone.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            route = .editor
                        }
                    },
                    findPages: { LibrarySearch.find($0, in: viewModel.library) },
                    onOpenPage: { hit in
                        route = nil
                        // Let the cover dismiss before pushing reading mode.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            path.append(NoteRef(collectionID: hit.collectionID, noteID: hit.memory.id))
                        }
                    },
                    onOpenDraft: { draft in
                        route = nil
                        // Same dance: swap covers only after this one is gone.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            route = .draft(Memory(title: draft.title, body: draft.body))
                        }
                    }
                )
                .environment(\.theme, Theme(appearance: .system))
            }
        }
    }
}

extension HomeFlow {
    /// Text the page `route` opens holds only to prompt the writer.
    private static func prompts(of route: Route) -> [CanvasItem.ID: String] {
        if case .draft(_, let prompts, _) = route { return prompts }
        return [:]
    }

    /// The push `route` was drafted from, if any.
    private static func pushId(of route: Route) -> String? {
        if case .draft(_, _, let pushId) = route { return pushId }
        return nil
    }

    /// UI tests launch with `-UITEST` for a fresh, non-persistent seed each run.
    /// The trigger's (`-UITEST-TRIGGER`) save to a file of their own, emptied
    /// at launch unless `-KEEP_SETTINGS`, so a saved draft survives a relaunch.
    private static func makeStore() -> CollectionStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST-TRIGGER") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-trigger-collections.json")
            if !arguments.contains("-KEEP_SETTINGS") { try? FileManager.default.removeItem(at: file) }
            return FileCollectionStore(url: file)
        }
        if arguments.contains("-UITEST") {
            return InMemoryCollectionStore(collections: MemoryCollection.seed)
        }
        #endif
        return FileCollectionStore()
    }

    /// UI tests keep their Home as it was, unless they test the trigger.
    private static var triggerEntryAllowed: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST") { return arguments.contains("-UITEST-TRIGGER") }
        // The unit tests' host app: no prompts, no live library or backend.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #endif
        return true
    }

    /// The push in `router.pending`: its saved record, with the photos still
    /// in the library -- three or more play; fewer, Home stays quietly
    /// (handoff 7.6, D4). Never regroups, never asks the backend.
    ///
    /// While another cover is up (a page being edited, chat, another
    /// story) the push waits in `router.pending` and opens once that cover
    /// has closed: tearing it down would lose an unsaved page. An alert or
    /// a sheet on Home holds it the same way (a cover asked for under one
    /// never shows), and it leaves `router.pending` only once its story is
    /// on screen.
    private func openPendingPush() async {
        guard let pushId = router.pending, keeper.mayOpenPush(coverUp: route != nil) else { return }
        let records = trigger.records
        guard let record = pushId == "latest" ? records.latest() : records.record(pushId) else {
            return finishPending(pushId)
        }
        let present = await trigger.photos.existing(Array(record.photoIds.values))
        let numbers = Set(record.photoIds.filter { present.contains($0.value) }.keys)
        guard let memory = record.memory.replacingMissing(present: numbers) else { return finishPending(pushId) }
        // A cover may have opened, or a newer push arrived, while the library
        // was asked: then this one waits (or gives way) and runs again.
        guard await RootPresentation.waitUntilBare(),
              keeper.mayOpenPush(coverUp: route != nil), router.pending == pushId else { return }
        route = .trigger(TriggerOpening(pushId: record.pushId, memory: memory, photoIds: record.photoIds,
                                        bucketId: record.bucketId, request: pushId))
    }

    /// The story of an opened push, its menu and ending wired to the scheduler.
    private func triggerStory(_ opening: TriggerOpening) -> some View {
        PhotoTriggerView(memory: opening.memory, bucketName: opening.bucketName,
                         allowsFewer: opening.allowsFewer, photoIds: opening.photoIds,
                         library: trigger.photos, onClose: { route = nil },
                         onKeep: { keepTrigger($0, opening: opening) },
                         onMenu: { trigger.menu($0, pushId: opening.pushId) },
                         onFinished: { trigger.storyFinished(opening.pushId) })
            .onAppear { if let request = opening.request { finishPending(request) } }
    }

    /// Clears `pushId` from the router -- never a newer push that came in
    /// meanwhile (two quick taps).
    private func finishPending(_ pushId: String) {
        if router.pending == pushId { router.pending = nil }
    }

    /// The ending's button: the photos and words as a canvas draft, opened
    /// only over the story that asked for it (`TriggerKeep`).
    private func keepTrigger(_ memory: TriggerMemory, opening: TriggerOpening) {
        let photos = trigger.photos
        let covers = TriggerKeep.Covers(
            story: { storyOnScreen },
            isEmpty: { route == nil },
            close: { route = nil },
            open: { route = .draft($0.page, prompts: $0.prompts, pushId: opening.pushId) },
            discard: { TriggerDraftMaker.discard($0.page) }
        )
        Task { @MainActor in
            await keeper.keep(opening.id, make: {
                await TriggerDraftMaker.make(memory, photoIds: opening.photoIds, photos: photos)
            }, covers: covers)
        }
    }

    /// The story on screen, if the cover is one.
    private var storyOnScreen: UUID? {
        if case .trigger(let opening) = route { return opening.id }
        return nil
    }
}
