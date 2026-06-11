import MiraNoteKit
import SwiftUI

/// Sketch 2: free canvas with long-press insert menu, Save and
/// Quick organize in the top bar, expandable toolbar at the bottom.
struct CanvasView: View {
    // The view model is @State-owned so it survives re-renders of the
    // parent's navigationDestination closure; a plain stored property
    // would be rebuilt blank every time Home re-renders (e.g. after Save).
    @State private var viewModel: CanvasViewModel
    private let onSave: ((Memory) -> Void)?

    /// Shared coordinate space for the long-press location, the insert
    /// menu, and item positions -- the background ignores the safe area,
    /// so its .local space is offset from the ZStack's by the top inset.
    private static let canvasSpace = "canvas"

    @State private var activeSheet: CanvasSheet?
    @State private var showsAIChooser = false
    @State private var pendingInsertPoint: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero

    init(memory: Memory, onSave: ((Memory) -> Void)? = nil) {
        _viewModel = State(initialValue: CanvasViewModel(memory: memory))
        self.onSave = onSave
    }

    enum CanvasSheet: Identifiable {
        case text
        case aiSticker
        case styleTransfer

        var id: Int {
            switch self {
            case .text: return 0
            case .aiSticker: return 1
            case .styleTransfer: return 2
            }
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return GeometryReader { proxy in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                    .onAppear { canvasSize = proxy.size }
                    .onTapGesture { viewModel.insertMenuLocation = nil }
                    .gesture(longPressWithLocation)

                ForEach(viewModel.items) { item in
                    CanvasItemView(item: item) { newPosition in
                        viewModel.move(itemID: item.id, to: newPosition)
                    }
                }

                if let location = viewModel.insertMenuLocation {
                    InsertMenu(location: location) { choice in
                        viewModel.insertMenuLocation = nil
                        pendingInsertPoint = location
                        switch choice {
                        case .text: activeSheet = .text
                        case .image: activeSheet = .styleTransfer
                        case .ai: showsAIChooser = true
                        }
                    }
                }
            }
            .coordinateSpace(name: Self.canvasSpace)
        }
        .navigationTitle("Canvas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Save") {
                    viewModel.save()
                    onSave?(viewModel.memory)
                }
                Button("Quick organize") {
                    viewModel.quickOrganize(canvasWidth: max(canvasSize.width, Theme.canvasSpacing))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            CanvasToolbar(
                isDrawerExpanded: $viewModel.isDrawerExpanded,
                onPickSticker: { sticker in
                    viewModel.addSticker(sticker, at: centerPoint)
                },
                onText: {
                    pendingInsertPoint = centerPoint
                    activeSheet = .text
                },
                onPhoto: {
                    pendingInsertPoint = centerPoint
                    activeSheet = .styleTransfer
                },
                onAI: {
                    pendingInsertPoint = centerPoint
                    showsAIChooser = true
                }
            )
        }
        // D2: AI Sticker and Style Transfer stay separate entries; the
        // chooser is a dialog so sheet identity never swaps mid-present.
        .confirmationDialog("AI tools", isPresented: $showsAIChooser, titleVisibility: .visible) {
            Button("AI Sticker") { activeSheet = .aiSticker }
            Button("Style Transfer") { activeSheet = .styleTransfer }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    /// SwiftUI's onLongPressGesture closure carries no touch location, so
    /// the long press is sequenced with a zero-distance drag whose end
    /// point supplies the menu position.
    private var longPressWithLocation: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace)))
            .onEnded { value in
                if case .second(true, let drag) = value, let location = drag?.location {
                    viewModel.insertMenuLocation = location
                }
            }
    }

    private var centerPoint: CGPoint {
        CGPoint(x: max(canvasSize.width / 2, 60), y: max(canvasSize.height / 2, 60))
    }

    @ViewBuilder private func sheetContent(for sheet: CanvasSheet) -> some View {
        switch sheet {
        case .text:
            TextInputSheet { text in
                viewModel.addText(text, at: pendingInsertPoint)
            }
        case .aiSticker:
            AIStickerSheet { sticker in
                viewModel.addSticker(sticker, at: pendingInsertPoint)
            }
        case .styleTransfer:
            StyleTransferSheet { images in
                viewModel.addImages(images, around: pendingInsertPoint)
            }
        }
    }
}

/// Sketch 2 long-press menu: Text / Image / AI.
private struct InsertMenu: View {
    enum Choice { case text, image, ai }

    let location: CGPoint
    let onChoose: (Choice) -> Void

    var body: some View {
        VStack(spacing: 8) {
            menuButton("Text", symbol: "textformat") { onChoose(.text) }
            menuButton("Image", symbol: "photo") { onChoose(.image) }
            menuButton("AI", symbol: "sparkles") { onChoose(.ai) }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .shadow(radius: 8)
        // Testability hook: lets UI tests locate the menu and assert it
        // appears at the touch point (the v1 coordinate-space regression).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.insertMenu")
        .position(location)
    }

    private func menuButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(minWidth: 88, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}

/// One item on the canvas, draggable.
private struct CanvasItemView: View {
    let item: CanvasItem
    let onMove: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        content
            .offset(dragOffset)
            .position(item.position)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        dragOffset = .zero
                        onMove(
                            CGPoint(
                                x: item.position.x + value.translation.width,
                                y: item.position.y + value.translation.height
                            )
                        )
                    }
            )
    }

    @ViewBuilder private var content: some View {
        switch item.content {
        case .text(let text):
            Text(text)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        case .image(let ref):
            VStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                Text(ref.displayName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 96, height: 96)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        case .sticker(let sticker):
            Image(systemName: sticker.symbolName)
                .font(.system(size: 44))
                .padding(12)
                .background(.thinMaterial, in: Circle())
        }
    }
}

#Preview {
    NavigationStack {
        CanvasView(memory: Memory())
    }
}
