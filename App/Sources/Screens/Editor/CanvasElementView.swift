import AVFoundation
import MiraNoteKit
import SwiftUI

/// Renders one canvas element by content type.
struct CanvasElementView: View {
    let item: CanvasItem
    let isSelected: Bool
    let isEditingText: Bool
    let isPlaying: Bool
    var imageStore = ImageFileStore()
    var text: Binding<String>
    var textFocus: FocusState<CanvasItem.ID?>.Binding
    var onTogglePlay: () -> Void
    var onEditNote: () -> Void

    var body: some View {
        switch item.content {
        case .text(let block):
            textView(block)
        case .image(let ref):
            imageView(ref)
                .accessibilityIdentifier("element.image")
        case .sticker(let sticker):
            stickerView(sticker)
                .accessibilityIdentifier("element.sticker")
        case .sound(let clip):
            soundView(clip)
        }
    }

    /// Real pixels when the ref has a file (with its filter and frame
    /// treatments); the warm gradient placeholder otherwise.
    @ViewBuilder private func imageView(_ ref: ImageRef) -> some View {
        if let image = CanvasImageCache.image(
            fileName: ref.fileName,
            filterName: ref.filterName,
            store: imageStore
        ) {
            framed(ref.frameName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            GradientPlaceholder(tint: Self.tint(for: ref))
        }
    }

    @ViewBuilder private func framed<Content: View>(
        _ frameName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        switch PhotoFrame(rawValue: frameName) ?? .none {
        case .none:
            content()
                .clipShape(RoundedRectangle(cornerRadius: Metrics.imageCorner))
        case .white:
            content()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                .shadow(color: Palette.ink.opacity(0.10), radius: 5, y: 2)
        case .polaroid:
            content()
                .clipShape(Rectangle())
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 26, trailing: 8))
                .background(Rectangle().fill(.white))
                .shadow(color: Palette.ink.opacity(0.14), radius: 7, y: 3)
        }
    }

    @ViewBuilder private func stickerView(_ sticker: GeneratedSticker) -> some View {
        if let image = CanvasImageCache.image(
            fileName: sticker.fileName,
            filterName: "",
            store: imageStore
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            StickerBlob(symbol: sticker.symbolName, label: sticker.prompt, size: min(item.size.width, item.size.height))
        }
    }

    @ViewBuilder private func textView(_ block: TextBlock) -> some View {
        if isEditingText {
            TextField("Say something...", text: text, axis: .vertical)
                .font(font(for: block))
                .foregroundStyle(Palette.color(named: block.colorName))
                .focused(textFocus, equals: item.id)
                .accessibilityIdentifier("canvas.textEditor")
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Palette.paper.opacity(0.75))
                )
        } else {
            Text(block.text.isEmpty ? "Say something..." : block.text)
                .font(font(for: block))
                .foregroundStyle(
                    block.text.isEmpty
                        ? Palette.textSecondary
                        : Palette.color(named: block.colorName)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
        }
    }

    private func font(for block: TextBlock) -> Font {
        // Larger blocks are display type and take the serif identity.
        block.pointSize >= 24
            ? Serif.font(size: block.pointSize, weight: 560, optical: 72)
            : Font.system(size: block.pointSize)
    }

    private func soundView(_ clip: SoundClip) -> some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.forest))
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isSelected)
            .accessibilityIdentifier("sound.play")

            Button(action: onEditNote) {
                HStack(spacing: 6) {
                    Text(clip.note.isEmpty ? "Add a note" : clip.note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(clip.note.isEmpty ? Palette.textSecondary : Palette.ink)
                        .lineLimit(1)
                    Text(Self.timestamp(clip.duration))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Palette.onInk.opacity(0.9))
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isSelected)
            .accessibilityIdentifier("sound.note")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func timestamp(_ duration: TimeInterval) -> String {
        let total = max(1, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func tint(for ref: ImageRef) -> Color {
        let tints = [Palette.tan, Palette.sage, Palette.taupe]
        let index = abs(ref.displayName.hashValue) % tints.count
        return tints[index]
    }
}

/// Plays one sound clip at a time; `playingID` drives the marker's state.
@MainActor
@Observable
final class SoundPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    var playingID: UUID?

    func toggle(clip: SoundClip, store: SoundFileStore) {
        if playingID == clip.id {
            stop()
            return
        }
        stop()
        guard store.exists(fileName: clip.fileName),
              let audioPlayer = try? AVAudioPlayer(contentsOf: store.url(forFileName: clip.fileName)) else {
            return
        }
        #if os(iOS)
        // Playback category so markers are audible with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player = audioPlayer
        audioPlayer.play()
        playingID = clip.id
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(audioPlayer.duration + 0.2))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        playingID = nil
    }
}
