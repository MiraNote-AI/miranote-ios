import MiraNoteKit
import SwiftUI

/// The on-canvas photo edit panel (v2.1): three chips -- instant filters
/// (page-aware "Match page" first), scrapbook frames, and Make sticker
/// (cutout + outline through the image studio; one undo step back).
struct PhotoEditPanel: View {
    @Bindable var editor: CanvasViewModel
    let itemID: CanvasItem.ID
    var studio: ImageStudioService
    var onClose: () -> Void

    @State private var section: Section = .filters
    @State private var cutoutTarget = ""
    @State private var stickering = false
    @State private var notice: String?

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore()

    var body: some View {
        ContextCard(title: "Edit photo") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sectionChip("Filters", .filters)
                    sectionChip("Frame", .frame)
                    sectionChip("Make sticker", .sticker)
                    Spacer()
                    Button("Done") { onClose() }
                        .font(.miraLabel)
                        .foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("photo.done")
                }

                switch section {
                case .filters: filterRow
                case .frame: frameRow
                case .sticker: stickerRow
                }

                if let notice {
                    Text(notice)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var currentRef: ImageRef? {
        if case .image(let ref) = editor.item(itemID)?.content { return ref }
        return nil
    }

    private func sectionChip(_ label: String, _ value: Section) -> some View {
        Button {
            section = value
        } label: {
            Chip(text: label, selected: section == value, compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo.section.\(value.rawValue)")
    }

    /// Instant presets; the selected one is filled. "Match page" leads.
    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(PhotoFilter.allCases) { filter in
                Button {
                    editor.setImageFilter(itemID: itemID, to: filter == .none ? "" : filter.rawValue)
                } label: {
                    Chip(
                        text: filter.label,
                        selected: (currentRef?.filterName ?? "") == (filter == .none ? "" : filter.rawValue),
                        compact: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photo.filter.\(filter.rawValue)")
            }
            Spacer()
        }
    }

    private var frameRow: some View {
        HStack(spacing: 8) {
            ForEach(PhotoFrame.allCases) { frame in
                Button {
                    editor.setImageFrame(itemID: itemID, to: frame == .none ? "" : frame.rawValue)
                } label: {
                    Chip(
                        text: frame.label,
                        selected: (currentRef?.frameName ?? "") == (frame == .none ? "" : frame.rawValue),
                        compact: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photo.frame.\(frame.rawValue)")
            }
            Spacer()
        }
    }

    private var stickerRow: some View {
        HStack(spacing: 8) {
            TextField("Describe what to keep (optional)", text: $cutoutTarget)
                .font(.miraCaption)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .accessibilityIdentifier("photo.cutout.target")
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Palette.paper)
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )

            Button {
                makeSticker()
            } label: {
                Text(stickering ? "Working..." : "Make sticker")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .disabled(stickering)
            .accessibilityIdentifier("photo.makeSticker")
        }
    }

    /// Cutout -> outline -> replace in place; the sticker joins favorites.
    /// Nothing on the canvas changes unless the whole pipeline succeeds.
    private func makeSticker() {
        guard !stickering, let ref = currentRef,
              let data = imageStore.data(forFileName: ref.fileName) else {
            notice = "This picture has no stored pixels to cut."
            return
        }
        stickering = true
        notice = nil
        let target = cutoutTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { stickering = false }
            do {
                let cut = try await studio.cutout(image: data, target: target.isEmpty ? nil : target)
                let outlined = try await studio.outline(image: cut)
                let fileName = try imageStore.save(outlined, id: UUID())
                let sticker = GeneratedSticker(
                    prompt: target.isEmpty ? ref.displayName : target,
                    symbolName: "sparkles",
                    fileName: fileName
                )
                editor.replaceImageWithSticker(itemID: itemID, sticker: sticker)
                favoritesStore.add(sticker)
                onClose()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}

private enum Section: String {
    case filters, frame, sticker
}
