import MiraNoteKit
import SwiftUI

/// Every Flow 7 scene, addressable by a stable id. Drives the DEBUG snapshot
/// harness (`-MIRANOTE_SCREEN <id>`) and the in-app scene switching.
enum FlowScene: String, CaseIterable {
    case home
    case canvas
    case voice
    case text
    case textStory
    case imageStart
    case photoLibrary
    case filter
    case aiSticker
    case stickerLibrary
    case export
    case chat
    case collection
    case note

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .home: HomeView(viewModel: HomeViewModel(collections: MemoryCollection.seed))
        case .canvas: CanvasScene()
        case .voice: VoiceScene()
        case .text: TextInputScene()
        case .textStory: TextStoryScene()
        case .imageStart: ImageStartScene()
        case .photoLibrary: PhotoLibraryScene()
        case .filter: FilterScene()
        case .aiSticker: AIStickerScene()
        case .stickerLibrary: StickerLibraryScene()
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

/// Renders a filled note in the editor for the DEBUG catalog.
private struct NoteCatalogPreview: View {
    @State private var viewModel = HomeViewModel(collections: [
        MemoryCollection(title: "Daily Log", memories: [
            Memory(
                title: "Lunch by the river",
                body: "Sunny afternoon, tiny noodle shop by the bridge. Warm broth, golden light."
            )
        ])
    ])

    var body: some View {
        let collection = viewModel.collections.first
        NoteDetailView(
            viewModel: viewModel,
            collectionID: collection?.id ?? UUID(),
            noteID: collection?.memories.first?.id ?? UUID()
        )
    }
}
