import MiraNoteKit
import SwiftUI

/// The interactive editor. The canvas is home base: Background, Voice and
/// Text act directly on it, Image and Sticker open their panel scenes, and
/// Done composes the memory (title from its most prominent text) and files it.
struct EditorFlowView: View {
    var onExit: () -> Void = {}
    var onComplete: (Memory) -> Void = { _ in }
    /// Files the page quietly WITHOUT leaving the editor -- the autosave
    /// half of "editing autosaves"; like Home, it keeps a draft (#137).
    var onAutosave: (Memory) -> Void = { _ in }
    var recorderFactory: @MainActor () -> AudioRecording = { AudioRecorder() }
    var services: ServiceContainer = .mock

    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: CanvasViewModel
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
    /// draft opens.
    init(
        memory: Memory? = nil,
        onExit: @escaping () -> Void = {},
        onComplete: @escaping (Memory) -> Void = { _ in },
        onAutosave: @escaping (Memory) -> Void = { _ in },
        recorderFactory: @escaping @MainActor () -> AudioRecording = { AudioRecorder() },
        services: ServiceContainer = .mock
    ) {
        self.onExit = onExit
        self.onComplete = onComplete
        self.onAutosave = onAutosave
        self.recorderFactory = recorderFactory
        self.services = services
        // A fresh memory starts BLANK (v2.1) and unsaved (#137); the
        // Mira-generated draft is the recorded D3 backend gap and takes
        // over here when it lands.
        _editor = State(initialValue: CanvasViewModel(
            memory: memory?.materializedForEditing() ?? Memory(isDraft: true)
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
                if scenePhase == .background && !editor.isBlankPage,
                   let page = editor.autosavedMemory {
                    onAutosave(page)
                }
            }
    }

    /// Leaving keeps the words (autosave semantics): Save and Home both
    /// file a page with anything on it -- a background alone counts; only
    /// an untouched blank page keeps nothing -- no junk "New memory"
    /// entries in the journal. Only Save files it saved (#137).
    private func finish(saving: Bool) {
        if editor.isBlankPage {
            onExit()
        } else {
            onComplete(editor.leave(saving: saving))
        }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .canvas:
            CanvasScene(
                editor: editor,
                mira: mira,
                imageStudio: services.imageStudio,
                actions: actions(back: { finish(saving: false) }, done: { finish(saving: true) }),
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
    /// Home left a page without Save (#137): a toast says it was kept,
    /// once the editor is gone.
    @State private var draftToastPending = false
    @State private var draftToastShown = false
    @State private var draftToastDismiss: Task<Void, Never>?

    /// Where a newly finished memory is filed by default.
    private static let inbox = "Daily Log"

    /// A note addressed within its collection, for stack navigation.
    private struct NoteRef: Hashable {
        let collectionID: MemoryCollection.ID
        let noteID: Memory.ID
    }

    /// UI tests launch with `-UITEST` for a fresh, non-persistent seed each run.
    private static func makeStore() -> CollectionStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            return InMemoryCollectionStore(collections: MemoryCollection.seed)
        }
        #endif
        return FileCollectionStore()
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
        /// A page Mira drafted in chat, opening in the editor as a new note.
        case draft(Memory)

        var id: String {
            switch self {
            case .editor: return "editor"
            case .editorIn(let journal): return "editor-in-\(journal.uuidString)"
            case .editMemory(let memory): return "edit-\(memory.id.uuidString)"
            case .chat: return "chat"
            case .draft(let memory): return "draft-\(memory.id.uuidString)"
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
                onOpenProfile: { path.append(AccountRoute.profile) }
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
        .overlay(alignment: .bottom) {
            if draftToastShown {
                SaveToast(message: .keptAsDraft)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        // The Appearance setting, applied live (a choice redraws at once).
        .environment(\.theme, Theme(appearance: settings.appearance))
        #if DEBUG
        .background { ChatPhotoFilesProbe() }
        // Under a cover the scene's own probe shows too; nothing here listens.
        .background(DebugStateProbe { ["scene": "home", "listening": [String: Bool]()] })
        #endif
        .fullScreenCover(item: $route, onDismiss: showPendingDraftToast) { presented in
            switch presented {
            case .editor, .editorIn:
                let journal = presented.journal
                EditorFlowView(
                    onExit: { route = nil },
                    onComplete: { memory in
                        viewModel.file(memory, inCollection: journal, orTitled: Self.inbox)
                        draftToastPending = memory.isDraft
                        judgeMoods([memory.id])
                        route = nil
                    },
                    onAutosave: { viewModel.file($0, inCollection: journal, orTitled: Self.inbox) },
                    recorderFactory: Self.makeRecorder,
                    services: Self.editorServices(base: services)
                )
                // The editor, its tools and Mira chat stay on System.
                .environment(\.theme, Theme(appearance: .system))
            case .editMemory(let memory), .draft(let memory):
                EditorFlowView(
                    memory: memory,
                    onExit: { route = nil },
                    onComplete: { edited in
                        viewModel.file(edited, underCollectionTitled: Self.inbox)
                        draftToastPending = edited.isDraft
                        judgeMoods([edited.id])
                        route = nil
                    },
                    onAutosave: { viewModel.file($0, underCollectionTitled: Self.inbox) },
                    recorderFactory: Self.makeRecorder,
                    services: Self.editorServices(base: services)
                )
                .environment(\.theme, Theme(appearance: .system))
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
                            route = .draft(Memory(title: draft.title, body: draft.body, isDraft: true))
                        }
                    }
                )
                .environment(\.theme, Theme(appearance: .system))
            }
        }
    }

    /// Not under the editor as it slides away: the toast's two seconds,
    /// and its spoken line, start once it is gone.
    private func showPendingDraftToast() {
        guard draftToastPending else { return }
        draftToastPending = false
        showDraftToast()
    }

    /// The export toast's look for two seconds; taps go through to the
    /// screen under it.
    private func showDraftToast() {
        draftToastDismiss?.cancel()
        withAnimation(.spring(duration: 0.3)) { draftToastShown = true }
        draftToastDismiss = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { draftToastShown = false }
        }
    }
}
