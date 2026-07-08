import MiraNoteKit
import SwiftUI

/// The interactive editor. The canvas is home base (v2.1): Text and Sound
/// act directly on it, Image opens its panel scenes, and Done composes the
/// memory (title from its most prominent text) and files it.
struct EditorFlowView: View {
    var onExit: () -> Void = {}
    var onComplete: (Memory) -> Void = { _ in }
    var recorderFactory: @MainActor () -> AudioRecording = { AudioRecorder() }
    var services: ServiceContainer = .mock

    @State private var editor: CanvasViewModel
    @State private var mira: MiraCanvasCoordinator
    @State private var scene: FlowScene = .canvas
    @State private var pendingTool: EditorMode?

    /// Pass `memory` to edit an existing page; omitted, a fresh starter
    /// draft opens.
    init(
        memory: Memory? = nil,
        onExit: @escaping () -> Void = {},
        onComplete: @escaping (Memory) -> Void = { _ in },
        recorderFactory: @escaping @MainActor () -> AudioRecording = { AudioRecorder() },
        services: ServiceContainer = .mock
    ) {
        self.onExit = onExit
        self.onComplete = onComplete
        self.recorderFactory = recorderFactory
        self.services = services
        // A fresh memory starts BLANK (v2.1); the Mira-generated draft is
        // the recorded D3 backend gap and takes over here when it lands.
        _editor = State(initialValue: CanvasViewModel(
            memory: memory?.materializedForEditing() ?? Memory()
        ))
        _mira = State(initialValue: MiraCanvasCoordinator(
            text: services.textTransform,
            chat: services.chat
        ))
    }

    var body: some View {
        content
            .id(scene)
            .transition(.opacity)
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .canvas:
            CanvasScene(
                editor: editor,
                mira: mira,
                imageStudio: services.imageStudio,
                actions: actions(back: onExit, done: {
                    // Done on an untouched blank page keeps nothing -- no
                    // junk "New memory" entries in the journal.
                    if editor.items.isEmpty {
                        onExit()
                    } else {
                        onComplete(editor.composedMemory())
                    }
                }),
                pendingTool: $pendingTool,
                recorderFactory: recorderFactory,
                transcription: services.voiceTranscription
            )
        case .imageStart:
            ImagePanelScene(
                editor: editor,
                studio: services.imageStudio,
                actions: actions(back: { navigate(.canvas) }, done: { navigate(.canvas) })
            )
        case .home, .chat, .collection, .note, .export:
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

    /// Text and Sound always act on the canvas; from another scene they
    /// carry over as a pending tool the canvas consumes on arrival.
    private func select(mode: EditorMode) {
        switch mode {
        case .image:
            navigate(.imageStart)
        case .text, .sound:
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

    /// UI tests record with a canned in-memory recorder (no mic permission).
    @MainActor private static func makeRecorder() -> AudioRecording {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            return MockAudioRecorder()
        }
        #endif
        return AudioRecorder()
    }

    private enum Route: Identifiable {
        case editor
        case editMemory(Memory)
        case chat(String)

        var id: String {
            switch self {
            case .editor: return "editor"
            case .editMemory(let memory): return "edit-\(memory.id.uuidString)"
            case .chat: return "chat"
            }
        }
    }

    /// Navigation token for the recently-deleted bin.
    struct TrashRoute: Hashable {}

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                viewModel: viewModel,
                onStart: { route = .editor },
                onQuickCapture: { route = .chat($0) },
                onOpenCollection: { path.append($0) },
                onOpenTrash: { path.append(TrashRoute()) }
            )
            .navigationBarHidden(true)
            .navigationDestination(for: MemoryCollection.self) { collection in
                CollectionDetailView(
                    viewModel: viewModel,
                    collectionID: collection.id,
                    onBack: { path.removeLast() },
                    onOpenNote: { path.append(NoteRef(collectionID: collection.id, noteID: $0.id)) }
                )
                .navigationBarHidden(true)
            }
            .navigationDestination(for: NoteRef.self) { ref in
                if let memory = viewModel.note(ref.noteID, in: ref.collectionID) {
                    ReadingView(
                        memory: memory,
                        onBack: { path.removeLast() },
                        onEdit: { route = .editMemory(memory) }
                    )
                    .navigationBarHidden(true)
                }
            }
            .navigationDestination(for: TrashRoute.self) { _ in
                RecentlyDeletedView(
                    viewModel: viewModel,
                    onBack: { path.removeLast() }
                )
                .navigationBarHidden(true)
            }
        }
        .fullScreenCover(item: $route) { presented in
            switch presented {
            case .editor:
                EditorFlowView(
                    onExit: { route = nil },
                    onComplete: { memory in
                        viewModel.file(memory, underCollectionTitled: Self.inbox)
                        route = nil
                    },
                    recorderFactory: Self.makeRecorder,
                    services: Self.editorServices(base: services)
                )
            case .editMemory(let memory):
                EditorFlowView(
                    memory: memory,
                    onExit: { route = nil },
                    onComplete: { edited in
                        viewModel.file(edited, underCollectionTitled: Self.inbox)
                        route = nil
                    },
                    recorderFactory: Self.makeRecorder,
                    services: Self.editorServices(base: services)
                )
            case .chat(let seed):
                MiraChatView(
                    service: services.chat,
                    seed: seed,
                    onExit: { route = nil },
                    onNewMemory: {
                        viewModel.file(Memory(title: seed), underCollectionTitled: Self.inbox)
                        route = nil
                    },
                    findPages: { LibrarySearch.find($0, in: viewModel.library) },
                    onOpenPage: { hit in
                        route = nil
                        // Let the cover dismiss before pushing reading mode.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            path.append(NoteRef(collectionID: hit.collectionID, noteID: hit.memory.id))
                        }
                    }
                )
            }
        }
    }
}
