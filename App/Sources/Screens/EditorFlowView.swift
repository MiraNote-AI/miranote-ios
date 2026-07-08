import MiraNoteKit
import SwiftUI

/// The interactive editor. The canvas is home base (v2.1): Text and Sound
/// act directly on it, Image opens its panel scenes, and Done composes the
/// memory (title from its most prominent text) and files it.
struct EditorFlowView: View {
    var onExit: () -> Void = {}
    var onComplete: (Memory) -> Void = { _ in }
    var recorderFactory: () -> AudioRecording = { AudioRecorder() }

    @State private var editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    @State private var scene: FlowScene = .canvas
    @State private var pendingTool: EditorMode?

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
                actions: actions(back: onExit, done: { onComplete(editor.composedMemory()) }),
                pendingTool: $pendingTool,
                recorderFactory: recorderFactory
            )
        case .imageStart:
            ImageStartScene(
                actions: actions(onGo: { navigate(.photoLibrary) }),
                onGenerate: { navigate(.aiSticker) }
            )
        case .photoLibrary:
            PhotoLibraryScene(actions: actions(onGo: { navigate(.filter) }, back: { navigate(.canvas) }))
        case .filter:
            FilterScene(actions: actions(onGo: { navigate(.canvas) }))
        case .aiSticker:
            AIStickerScene(actions: actions(onGo: { navigate(.stickerLibrary) }, back: { navigate(.imageStart) }))
        case .stickerLibrary:
            StickerLibraryScene(actions: actions(onGo: { navigate(.canvas) }))
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

    /// UI tests record with a canned in-memory recorder (no mic permission).
    private static func makeRecorder() -> AudioRecording {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            return MockAudioRecorder()
        }
        #endif
        return AudioRecorder()
    }

    private enum Route: Identifiable {
        case editor
        case chat(String)

        var id: String {
            switch self {
            case .editor: return "editor"
            case .chat: return "chat"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                viewModel: viewModel,
                onStart: { route = .editor },
                onQuickCapture: { route = .chat($0) },
                onOpenCollection: { path.append($0) }
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
                NoteDetailView(
                    viewModel: viewModel,
                    collectionID: ref.collectionID,
                    noteID: ref.noteID,
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
                    recorderFactory: Self.makeRecorder
                )
            case .chat(let seed):
                MiraChatView(
                    service: services.chat,
                    seed: seed,
                    onExit: { route = nil },
                    onNewMemory: {
                        viewModel.file(Memory(title: seed), underCollectionTitled: Self.inbox)
                        route = nil
                    }
                )
            }
        }
    }
}
