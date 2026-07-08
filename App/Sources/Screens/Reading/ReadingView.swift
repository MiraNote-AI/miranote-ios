import MiraNoteKit
import SwiftUI
import UIKit

/// Reading mode (v2.1): the finished page, full bleed -- where looking
/// happens, where sound plays, and where the share/export entry lives.
/// Editing is one tap away.
struct ReadingView: View {
    let memory: Memory
    var onBack: () -> Void = {}
    var onEdit: () -> Void = {}

    @State private var player = SoundPlayer()
    @State private var showsExport = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            StaticPageView(memory: memory, designWidth: 360, player: player)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
        }
        .screenBackground()
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                circleButton("chevron.left", id: "reading.back", action: onBack)
                Spacer()
                Text(memory.title)
                    .font(.miraScreenTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer()
                circleButton("square.and.arrow.up", id: "reading.share") { showsExport = true }
                circleButton("pencil", id: "reading.edit", action: onEdit)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
            .background(Palette.paper.opacity(0.94))
        }
        .sheet(isPresented: $showsExport) {
            ExportSheet(memory: memory)
                .presentationDetents([.medium])
        }
        .onDisappear { player.stop() }
    }

    private func circleButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Palette.onInk)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// The v2.1 export sheet: destinations first (Save to Photos / Share), the
/// long image is the only format, parameters live behind Advanced, and a
/// page with sound says plainly that audio stays in the app.
struct ExportSheet: View {
    let memory: Memory

    @State private var rendered: UIImage?
    @State private var renderedPNG: Data?
    @State private var advancedOpen = false
    @State private var confirmation: String?
    @State private var photoSaver = PhotoSaver()
    @Environment(\.dismiss) private var dismiss

    private var hasSound: Bool {
        memory.items.contains { if case .sound = $0.content { return true } else { return false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share this page")
                .font(.miraPageTitle)
                .foregroundStyle(Palette.ink)

            HStack(alignment: .top, spacing: 14) {
                preview
                VStack(spacing: 8) {
                    Button {
                        saveToPhotos()
                    } label: {
                        destinationLabel("Save to Photos", filled: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("export.photos")

                    shareButton

                    if hasSound {
                        Label {
                            Text("This page's sound plays in MiraNote only.")
                        } icon: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                    }
                    if let confirmation {
                        Text(confirmation)
                            .font(.miraCaption)
                            .foregroundStyle(Palette.forest)
                            .accessibilityIdentifier("export.confirmation")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            Button {
                advancedOpen.toggle()
            } label: {
                HStack {
                    Image(systemName: advancedOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Advanced")
                    Spacer()
                    Text("Long image \u{00B7} PNG")
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(.miraCaption)
                .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)

            if advancedOpen {
                Text("The page exports at 2x as one tall PNG named after it. PDF and print come later.")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        .task { render() }
    }

    private var preview: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Palette.cardFill)
            }
        }
        .frame(width: 88, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
        )
    }

    @ViewBuilder private var shareButton: some View {
        if let rendered, let data = renderedPNG {
            ShareLink(
                item: ExportedPage(data: data, title: memory.title),
                preview: SharePreview(memory.title, image: Image(uiImage: rendered))
            ) {
                destinationLabel("Share...", filled: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.share")
        } else {
            destinationLabel("Share...", filled: false)
                .opacity(0.5)
        }
    }

    private func destinationLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.miraPill)
            .foregroundStyle(filled ? Palette.onInk : Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(filled ? Palette.ink : Palette.onInk)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
            )
    }

    /// The long image: the page rendered at 2x with sound markers hidden
    /// (a speaker glyph nobody can tap reads as broken -- v2.1).
    @MainActor private func render() {
        let renderer = ImageRenderer(
            content: StaticPageView(memory: memory, designWidth: 360, showsSound: false)
        )
        renderer.scale = 2
        rendered = renderer.uiImage
        renderedPNG = rendered?.pngData()
    }

    private func saveToPhotos() {
        guard let rendered else { return }
        photoSaver.save(rendered) { succeeded in
            confirmation = succeeded
                ? "Saved to Photos."
                : "Couldn't save -- allow Photos access in Settings."
        }
    }
}

/// Bridges UIImageWriteToSavedPhotosAlbum's target-selector completion so
/// the sheet reports the truth (a denied permission fails silently
/// otherwise).
private final class PhotoSaver: NSObject {
    private var completion: ((Bool) -> Void)?

    func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(
            image,
            self,
            #selector(image(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }

    @objc private func image(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        completion?(error == nil)
        completion = nil
    }
}

/// Transferable wrapper so ShareLink hands receivers a named PNG.
struct ExportedPage: Transferable {
    let data: Data
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { page in
            page.data
        }
        .suggestedFileName { page in
            let slug = page.title
                .map { $0.isLetter || $0.isNumber ? $0 : "-" }
                .reduce(into: "") { partial, char in
                    if char != "-" || partial.last != "-" { partial.append(char) }
                }
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            return slug.isEmpty ? "MiraNote-page.png" : "\(slug).png"
        }
    }
}
