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
    @State private var aiInstruction = ""
    @State private var aiEditing = false
    @State private var notice: String?

    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    var body: some View {
        ContextCard(title: "Edit photo") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sectionChip("Filters", .filters)
                    sectionChip("Frame", .frame)
                    sectionChip("Make sticker", .sticker)
                    sectionChip("Ask AI", .ai, icon: "sparkles")
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
                case .ai: aiRow
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

    private func sectionChip(_ label: String, _ value: Section, icon: String? = nil) -> some View {
        Button {
            section = value
        } label: {
            Chip(text: label, selected: section == value, compact: true, systemImage: icon)
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
    case filters, frame, sticker, ai
}

// MARK: - Ask AI (stylize in place)

extension PhotoEditPanel {
    /// "Change the photo with words": remove the bin in the back, make it
    /// autumn, brighten it -- one instruction, new pixels in place.
    private var aiRow: some View {
        HStack(spacing: 8) {
            TextField("Tell AI what to change", text: $aiInstruction)
                .font(.miraCaption)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .accessibilityIdentifier("photo.ai.instruction")
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Palette.paper)
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )

            Button {
                runAIEdit()
            } label: {
                Text(aiEditing ? "Working..." : "Go")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .disabled(aiEditing || aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("photo.ai.run")
        }
    }

    private func runAIEdit() {
        let instruction = aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aiEditing, !instruction.isEmpty else { return }
        guard let ref = currentRef,
              let data = imageStore.data(forFileName: ref.fileName) else {
            notice = "This picture has no stored pixels to change."
            return
        }
        aiEditing = true
        notice = nil
        Task {
            defer { aiEditing = false }
            do {
                let edited = try await studio.stylize(image: data, instruction: instruction)
                let fileName = try imageStore.save(edited, id: UUID())
                editor.replaceImageFile(itemID: itemID, fileName: fileName)
                aiInstruction = ""
                notice = "Done -- take a look. Undo brings the old one back."
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}
