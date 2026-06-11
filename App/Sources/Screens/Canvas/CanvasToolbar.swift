import MiraNoteKit
import SwiftUI

/// Sketch 2 bottom bar: [sticker] [text] [photo] pills, AI bubble, and an
/// expand chevron (A1) that opens a WeChat-library-style sticker drawer.
struct CanvasToolbar: View {
    @Binding var isDrawerExpanded: Bool
    let onPickSticker: (GeneratedSticker) -> Void
    let onText: () -> Void
    let onPhoto: () -> Void
    let onAI: () -> Void

    /// Placeholder drawer content until the real sticker library exists.
    private let drawerSymbols = [
        "heart", "star", "sun.max", "moon", "cloud", "bolt",
        "leaf", "flame", "drop", "snowflake", "music.note", "gift"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("sticker") { withAnimation { isDrawerExpanded.toggle() } }
                    .buttonStyle(PillButtonStyle())
                Button("text", action: onText)
                    .buttonStyle(PillButtonStyle())
                Button("photo", action: onPhoto)
                    .buttonStyle(PillButtonStyle())

                Spacer()

                Button(action: onAI) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title3)
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    withAnimation { isDrawerExpanded.toggle() }
                } label: {
                    Image(systemName: isDrawerExpanded ? "chevron.down" : "chevron.up")
                        .font(.title3)
                }
                .buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isDrawerExpanded {
                stickerDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.regularMaterial)
    }

    private var stickerDrawer: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                ForEach(drawerSymbols, id: \.self) { symbol in
                    Button {
                        onPickSticker(GeneratedSticker(prompt: symbol, symbolName: symbol))
                    } label: {
                        Image(systemName: symbol)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .frame(height: 180)
    }
}
