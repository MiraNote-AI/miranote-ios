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
    /// While the compare control is held: the photo as it was when this
    /// panel opened, for the canvas to draw instead.
    @Binding var comparing: ImageRef?

    /// The photo when editing began: what Revert and Compare go back to.
    @State private var original: ImageRef?
    @GestureState private var holdingCompare = false
    @State private var section: Section = .filters
    @State private var cutoutTarget = ""
    @State private var stickering = false
    @State private var aiInstruction = ""
    @State private var aiEditing = false
    @State private var notice: String?

    private let imageStore = ImageFileStore()

    var body: some View {
        ContextCard(title: "Edit photo") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    sectionTab("Filters", .filters)
                    sectionTab("Frame", .frame)
                    sectionTab("Make sticker", .sticker)
                    sectionTab("Ask AI", .ai, icon: "sparkles")
                    Spacer()
                    Button("Done") { onClose() }
                        .font(.miraLabel)
                        .foregroundStyle(Palette.ink)
                        .fixedSize()
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

                if let original, let currentRef, looksEdited(currentRef, from: original) {
                    originalRow(original)
                }
            }
        }
        .onAppear { original = currentRef }
        .onDisappear { comparing = nil }
        // On the panel, not the row: the row leaves once the photo looks
        // unedited, and its handlers would leave with it.
        .onChange(of: holdingCompare) { _, holding in
            comparing = holding ? original : nil
        }
        // A visible change to the photo ends a comparison -- a filter
        // tapped mid-compare must show, not hide behind the original.
        .onChange(of: currentRef) { old, new in
            if let old, let new, looksEdited(new, from: old) { comparing = nil }
        }
    }

    /// What the eye sees -- a vision summary landing mid-session is not an
    /// edit to offer back.
    private func looksEdited(_ ref: ImageRef, from original: ImageRef) -> Bool {
        ref.fileName != original.fileName || ref.filterName != original.filterName
            || ref.frameName != original.frameName
    }

    /// Handoff screens 27-28: hold to see the photo as it was, or put it
    /// back in one (undoable) step.
    private func originalRow(_ original: ImageRef) -> some View {
        HStack(spacing: 8) {
            Label("Hold to compare", systemImage: "square.split.2x1")
                .font(.miraLabel)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(comparing == nil ? Palette.paper : Palette.tan.opacity(0.5)))
                .minimumHitTarget()
                // Gesture state, not onEnded: a hold the system cancels (a
                // call, Control Center) still lets go of the original.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($holdingCompare) { _, holding, _ in holding = true }
                )
                .accessibilityAddTraits(.isButton)
                // VoiceOver cannot hold: activating toggles the comparison.
                .accessibilityAction { comparing = comparing == nil ? original : nil }
                .accessibilityIdentifier("photo.compare")
            Button {
                comparing = nil
                editor.restoreImage(itemID: itemID, to: original)
                notice = nil
            } label: {
                Label("Revert", systemImage: "arrow.counterclockwise")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Palette.paper))
                    .minimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photo.revert")
            Spacer(minLength: 0)
        }
    }

    private var currentRef: ImageRef? {
        if case .image(let ref) = editor.item(itemID)?.content { return ref }
        return nil
    }

    /// Sections are TABS (text + underline), one level above the option
    /// chips below them -- they must not dress alike.
    private func sectionTab(_ label: String, _ value: Section, icon: String? = nil) -> some View {
        let active = section == value
        return Button {
            section = value
            // A notice narrates ONE action; it must not outlive its section.
            notice = nil
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(label)
                        .font(Sans.font(size: 13, weight: active ? 600 : 500))
                }
                .foregroundStyle(active ? Palette.ink : Palette.textSecondary)
                Capsule()
                    .fill(active ? Palette.ink : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo.section.\(value.rawValue)")
    }

    /// Instant presets; the selected one is filled. "Match page" leads.
    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(PhotoFilter.allCases) { filter in
                let selected = (currentRef?.filterName ?? "") == (filter == .none ? "" : filter.rawValue)
                Button {
                    editor.setImageFilter(itemID: itemID, to: filter == .none ? "" : filter.rawValue)
                } label: {
                    Chip(text: filter.label, selected: selected, compact: true)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
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
                // The new pixels on the page are the receipt; Undo brings
                // the old ones back.
                onClose()
                // New pixels, new sentence: refresh the vision summary.
                if let summary = try? await studio.describe(image: edited) {
                    editor.setImageSummary(itemID: itemID, to: summary)
                }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't work this time. Try again?"
            }
        }
    }
}
