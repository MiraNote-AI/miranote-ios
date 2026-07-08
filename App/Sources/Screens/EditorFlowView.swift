import MiraNoteKit
import SwiftUI

/// The interactive editor: shows one Flow 7 editor scene at a time and moves
/// between them as the instrument panel, Go, and nav controls are used.
/// A memory starts on the canvas; picking a mode swaps in that mode's scene,
/// Go advances the sub-steps, Save routes to Export, and Back unwinds.
struct EditorFlowView: View {
    var onExit: () -> Void = {}
    var onComplete: () -> Void = {}
    @State private var scene: FlowScene = .canvas

    var body: some View {
        content
            .id(scene)
            .transition(.opacity)
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case .canvas:
            // Done on the canvas finishes the memory: autosave semantics, no
            // Save step and no Export detour (export moves to reading mode in
            // Phase E).
            CanvasScene(actions: actions(onGo: { navigate(.text) }, back: onExit, done: onComplete))
        case .sound:
            VoiceScene(actions: actions(onGo: { navigate(.canvas) }))
        case .text:
            TextInputScene(actions: actions(onGo: { navigate(.textStory) }))
        case .textStory:
            TextStoryScene(actions: actions(onGo: { navigate(.canvas) }))
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
            AIStickerScene(actions: actions(onGo: { navigate(.stickerLibrary) }))
        case .stickerLibrary:
            StickerLibraryScene(actions: actions(onGo: { navigate(.canvas) }))
        case .export:
            ExportScene(actions: EditorActions(go: onComplete, leading: { navigate(.canvas) }, done: onComplete))
        case .home, .chat, .collection, .note:
            EmptyView()
        }
    }

    private func actions(
        onGo: (() -> Void)? = nil,
        back: (() -> Void)? = nil,
        done: (() -> Void)? = nil
    ) -> EditorActions {
        EditorActions(
            selectMode: { navigate(flowScene(for: $0)) },
            go: onGo ?? { navigate(.canvas) },
            leading: back ?? { navigate(.canvas) },
            done: done ?? { navigate(.canvas) }
        )
    }

    private func flowScene(for mode: EditorMode) -> FlowScene {
        switch mode {
        case .sound: return .sound
        case .text: return .text
        case .image: return .imageStart
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
                    onComplete: {
                        viewModel.file(Memory(title: "Lunch by the river"), underCollectionTitled: Self.inbox)
                        route = nil
                    }
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
