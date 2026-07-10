import MiraNoteKit
import SwiftUI

/// Non-interactive rendering of canvas elements, shared by journal covers,
/// reading mode, and the export image. Geometry matches the editor's
/// center-based model; `showsSound` lets the export hide markers (audio
/// cannot ride a PNG -- v2.1).
struct StaticPageView: View {
    let memory: Memory
    /// The width the editor laid the page out against.
    var designWidth: CGFloat = 360
    var showsSound = true
    var soundStore = SoundFileStore()
    var player: SoundPlayer?

    private var contentHeight: CGFloat {
        let bottom = memory.items.map { $0.position.y + $0.size.height / 2 }.max() ?? 0
        return max(620, bottom + 120)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Palette.onInk, Palette.cardFill.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            if memory.items.isEmpty {
                metadataFallback
            }
            ForEach(memory.items.sorted { $0.zIndex < $1.zIndex }) { item in
                element(item)
            }
        }
        .frame(width: designWidth, height: contentHeight)
    }

    /// Pages without canvas elements (legacy seeds, chat-filed notes) still
    /// read as pages: their archive title and body render in place.
    private var metadataFallback: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !memory.title.isEmpty {
                Text(memory.title)
                    .font(Serif.font(size: 30, weight: 560, optical: 72))
                    .foregroundStyle(Palette.ink)
            }
            if !memory.body.isEmpty {
                Text(memory.body)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(22)
        .frame(width: designWidth, alignment: .topLeading)
    }

    @ViewBuilder private func element(_ item: CanvasItem) -> some View {
        if showsSound || !isSound(item) {
            StaticElementView(item: item, soundStore: soundStore, player: player)
                .frame(width: item.size.width, height: item.size.height)
                .rotationEffect(.degrees(item.rotation))
                .position(item.position)
        }
    }

    private func isSound(_ item: CanvasItem) -> Bool {
        if case .sound = item.content { return true }
        return false
    }
}

/// One element, statically. Sound markers stay tappable when a player is
/// provided (reading mode); covers and exports pass none.
struct StaticElementView: View {
    let item: CanvasItem
    var imageStore = ImageFileStore()
    var soundStore = SoundFileStore()
    var player: SoundPlayer?

    var body: some View {
        switch item.content {
        case .text(let block):
            Text(block.text)
                .font(
                    block.pointSize >= 24
                        ? Serif.font(size: block.pointSize, weight: 560, optical: 72)
                        : Font.system(size: block.pointSize)
                )
                .foregroundStyle(Palette.color(named: block.colorName))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
        case .image(let ref):
            if let image = CanvasImageCache.image(
                fileName: ref.fileName, filterName: ref.filterName, store: imageStore
            ) {
                // Same trap as the editor: fill must be pinned to the box
                // and clipped, or portrait photos flood their neighbors.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.size.width, height: item.size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.imageCorner))
            } else {
                GradientPlaceholder(tint: Palette.tan)
            }
        case .sticker(let sticker):
            if let image = CanvasImageCache.image(
                fileName: sticker.fileName, filterName: "", store: imageStore
            ) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                StickerBlob(
                    symbol: sticker.symbolName,
                    label: sticker.prompt,
                    size: min(item.size.width, item.size.height)
                )
            }
        case .sound(let clip):
            soundMarker(clip)
        }
    }

    @ViewBuilder private func soundMarker(_ clip: SoundClip) -> some View {
        HStack(spacing: 8) {
            Button {
                player?.toggle(clip: clip, store: soundStore)
            } label: {
                Image(systemName: player?.playingID == clip.id ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.forest))
                    .symbolEffect(.variableColor.iterative, isActive: player?.playingID == clip.id)
            }
            .buttonStyle(.plain)
            .disabled(player == nil)
            .accessibilityIdentifier("reading.sound.play")

            Text(clip.note.isEmpty ? CanvasElementView.timestamp(clip.duration) : clip.note)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Palette.onInk.opacity(0.9))
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The little page thumbnail on the journal grid: the top of the page,
/// scaled down -- covers are first-screen crops (v2.1).
struct PageCoverView: View {
    let memory: Memory
    var coverWidth: CGFloat = 160
    var coverHeight: CGFloat = 200

    private let designWidth: CGFloat = 360

    var body: some View {
        let scale = coverWidth / designWidth
        // The scaled page rides in an overlay so its fixed design-size frame
        // never inflates the cover's layout (scaleEffect is visual only --
        // done naively the oversized invisible child overlaps neighboring
        // covers and breaks their hit testing).
        Color.clear
            .frame(width: coverWidth, height: coverHeight)
            .overlay(alignment: .topLeading) {
                StaticPageView(memory: memory, designWidth: designWidth, showsSound: true)
                    .scaleEffect(scale, anchor: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
            )
            .allowsHitTesting(false)
    }
}
