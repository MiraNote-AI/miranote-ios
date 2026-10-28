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
            store: imageStore,
            maxPixels: CanvasImageCache.displayPixels
        ) {
            framed(ref.frameName) {
                // Fill THEN pin to the element box and clip: without the
                // explicit frame, scaledToFill inflates layout to the
                // photo's long side and paints over neighbors.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.size.width, height: item.size.height)
                    .clipped()
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
            store: imageStore,
            maxPixels: CanvasImageCache.displayPixels
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
            // Words straight on the editing scrim (screens 11-20): no chip
            // behind them, only the block's own background if it has one.
            // The dark keyboard is the closest system match to the
            // handoff's forest keyboard.
            TextField(
                "Say something...",
                text: text,
                prompt: Text("Say something...").foregroundStyle(Palette.onInk.opacity(0.6)),
                axis: .vertical
            )
                .font(TextFace.font(for: block))
                .lineSpacing(TextFace.lineSpacing(for: block))
                .foregroundStyle(Palette.color(named: block.colorName))
                .tint(Palette.color(named: block.colorName))
                .multilineTextAlignment(block.alignment.textAlignment)
                .focused(textFocus, equals: item.id)
                .onChange(of: textFocus.wrappedValue == item.id, initial: true) { _, focused in
                    if focused { DarkKeyboard.apply() }
                }
                .accessibilityIdentifier("canvas.textEditor")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: block.alignment.frameAlignment)
                .padding(TextFace.inset)
                .textBlockBackground(block)
        } else {
            Text(block.text.isEmpty ? "Say something..." : block.text)
                .font(TextFace.font(for: block))
                .lineSpacing(TextFace.lineSpacing(for: block))
                .foregroundStyle(
                    block.text.isEmpty
                        ? Palette.textSecondary
                        : Palette.color(named: block.colorName)
                )
                .multilineTextAlignment(block.alignment.textAlignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: block.alignment.frameAlignment)
                .padding(TextFace.inset)
                .textBlockBackground(block)
        }
    }

    /// The marker's 42 pt pulse ring; the 30 pt tap circle sits inside it.
    static let soundRing: CGFloat = 42

    /// Handoff screen 09: the forest tap circle in its faint ring, then a
    /// frosted "tap to play" pill. Selected, the pill gives way to the note
    /// (or "Add a note") and the take's length.
    private func soundView(_ clip: SoundClip) -> some View {
        HStack(spacing: -1) {
            Button(action: onTogglePlay) {
                SoundMarkerGlyph(playing: isPlaying)
                    .frame(width: Self.soundRing, height: Self.soundRing)
                    .background(Circle().strokeBorder(Palette.forest.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isSelected)
            .accessibilityLabel(isPlaying ? "Stop" : "Play")
            .accessibilityIdentifier("sound.play")

            if isSelected {
                Button(action: onEditNote) {
                    HStack(spacing: 6) {
                        Text(clip.note.isEmpty ? "Add a note" : clip.note)
                            .font(Sans.font(size: 13, weight: 500))
                            .foregroundStyle(clip.note.isEmpty ? Palette.textSecondary : Palette.ink)
                            .lineLimit(1)
                        Text(Self.timestamp(clip.duration))
                            .font(Sans.font(size: 13, weight: 400))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(Palette.onInk.opacity(0.9))
                            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sound.note")
            } else {
                Text("tap to play")
                    .font(Sans.font(size: 12, weight: 700))
                    .foregroundStyle(Palette.forest)
                    .frame(width: 74, height: 24)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.58)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    )
                    .accessibilityIdentifier("sound.tapToPlay")
            }
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

/// The canvas text's keyboard in the dark appearance -- the closest system
/// match to the handoff's forest keyboard (screens 11-20). SwiftUI has no
/// keyboard-appearance modifier, so the field that just took focus (the
/// first responder) is set directly.
enum DarkKeyboard {
    @MainActor
    static func apply() {
        // After the focus change lands: the field is first responder then.
        DispatchQueue.main.async {
            guard let field = UIResponder.currentFirstResponder else { return }
            if let textView = field as? UITextView, textView.keyboardAppearance != .dark {
                textView.keyboardAppearance = .dark
                textView.reloadInputViews()
            } else if let textField = field as? UITextField, textField.keyboardAppearance != .dark {
                textField.keyboardAppearance = .dark
                textField.reloadInputViews()
            }
        }
    }
}

/// The caret of the text being written, in global (window) points: the
/// first responder's insertion point. Nil when no text field has focus.
enum WrittenCaret {
    @MainActor
    static var frame: CGRect? {
        guard let input = UIResponder.currentFirstResponder as? UIView & UITextInput,
              let end = input.selectedTextRange?.end else { return nil }
        let caret = input.caretRect(for: end)
        guard !caret.isNull, !caret.isInfinite else { return nil }
        return input.convert(caret, to: nil)
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?

    static var currentFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(captureFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func captureFirstResponder() {
        UIResponder.found = self
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
