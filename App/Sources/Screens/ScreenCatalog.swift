import MiraNoteKit
import SwiftUI

/// Every Flow 7 scene, addressable by a stable id. Drives the DEBUG snapshot
/// harness (`-MIRANOTE_SCREEN <id>`) and the in-app scene switching.
enum FlowScene: String, CaseIterable {
    case home
    case canvas
    case imageStart
    case sticker
    case export
    case chat
    case collection
    case note

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .home: HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
        case .canvas: CanvasCatalogPreview()
        case .imageStart: ImagePanelCatalogPreview()
        case .sticker: StickerPanelCatalogPreview()
        case .export: ExportScene()
        case .chat:
            MiraChatView(
                service: MockChatService(),
                seed: "Sunny afternoon, tiny noodle shop by the bridge"
            )
        case .collection:
            CollectionCatalogPreview()
        case .note:
            NoteCatalogPreview()
        }
    }
}

/// Renders the image panel with mock services for the DEBUG catalog.
private struct ImagePanelCatalogPreview: View {
    @State private var editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    @State private var pendingPlacement: PendingPlacement?

    var body: some View {
        ImagePanelScene(
            editor: editor,
            studio: MockImageStudioService(),
            pendingPlacement: $pendingPlacement
        )
    }
}

/// Renders the Sticker panel with mock services for the DEBUG catalog.
private struct StickerPanelCatalogPreview: View {
    @State private var editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    @State private var pendingPlacement: PendingPlacement?

    var body: some View {
        StickerPanelScene(
            editor: editor,
            studio: MockImageStudioService(),
            pendingPlacement: $pendingPlacement
        )
    }
}

/// Renders the live canvas editor seeded with the starter draft for the
/// DEBUG catalog (text and sound tools work in place; Image is inert here).
private struct CanvasCatalogPreview: View {
    @State private var editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    /// Mocks by default so the catalog stays offline and deterministic.
    /// MIRANOTE_CHAT_LIVE points it at the real backends instead -- the
    /// same affordance the chat scene already has, and the only way to
    /// exercise the seam between the app and a live canvas turn.
    @State private var mira = MiraCanvasCoordinator(
        text: Self.catalogLive
            ? ServiceContainer.live.textTransform : MockTextTransformService(),
        chat: Self.catalogLive ? ServiceContainer.live.chat : MockChatService(),
        imageStudio: Self.catalogLive
            ? ServiceContainer.live.imageStudio : MockImageStudioService()
    )
    /// `RootView.chatLive` only exists in DEBUG (it reads MIRANOTE_CHAT_LIVE).
    /// This catalog preview is dead code in a release build, so there it stays
    /// on mocks rather than failing to compile.
    private static var catalogLive: Bool {
        #if DEBUG
        return RootView.chatLive
        #else
        return false
        #endif
    }
    @State private var pendingTool: EditorMode?
    @State private var pendingPlacement: PendingPlacement?

    var body: some View {
        CanvasScene(
            editor: editor,
            mira: mira,
            pendingTool: $pendingTool,
            pendingPlacement: $pendingPlacement,
            recorderFactory: { MockAudioRecorder() }
        )
    }
}

/// Renders a seeded collection's detail for the DEBUG catalog, keeping the
/// view model and the opened id in sync.
private struct CollectionCatalogPreview: View {
    @State private var viewModel = HomeViewModel(collections: MemoryCollection.seed)

    var body: some View {
        CollectionDetailView(
            viewModel: viewModel,
            collectionID: viewModel.collections.first?.id ?? UUID()
        )
    }
}

/// Renders a filled page in reading mode for the DEBUG catalog.
private struct NoteCatalogPreview: View {
    var body: some View {
        ReadingView(memory: Memory(
            title: "Lunch by the river",
            items: Memory.starterDraft()
        ))
    }
}
