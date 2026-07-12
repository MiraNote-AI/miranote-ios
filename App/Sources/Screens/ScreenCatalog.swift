import MiraNoteKit
import SwiftUI

/// Every Flow 7 scene, addressable by a stable id. Drives the DEBUG snapshot
/// harness (`-MIRANOTE_SCREEN <id>`) and the in-app scene switching.
enum FlowScene: String, CaseIterable {
    case home
    case canvas
    case imageStart
    case libraryPanel
    case export
    case chat
    case collection
    case note

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .home: HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
        case .canvas: CanvasCatalogPreview()
        case .imageStart: ImagePanelCatalogPreview()
        case .libraryPanel: LibraryPanelCatalogPreview()
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

    var body: some View {
        ImagePanelScene(editor: editor, studio: MockImageStudioService())
    }
}

/// Renders the library panel for the DEBUG catalog.
private struct LibraryPanelCatalogPreview: View {
    @State private var editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))

    var body: some View {
        LibraryPanelScene(editor: editor)
    }
}

/// Renders the live canvas editor seeded with the starter draft for the
/// DEBUG catalog (text and sound tools work in place; Image is inert here).
private struct CanvasCatalogPreview: View {
    @State private var editor = CanvasViewModel(memory: Memory(items: Memory.starterDraft()))
    @State private var mira = MiraCanvasCoordinator(
        text: MockTextTransformService(),
        chat: MockChatService()
    )
    @State private var pendingTool: EditorMode?

    var body: some View {
        CanvasScene(
            editor: editor,
            mira: mira,
            pendingTool: $pendingTool,
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
