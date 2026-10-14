import Foundation
import MiraNoteKit
import SwiftUI

// Shared state shapes for CanvasScene's bottom cluster.

enum RecorderState {
    case idle
    /// The Voice tool is open but the mic is not live yet -- recording
    /// starts only when the user presses Record.
    case armed
    case recording(start: Date)
    case review(data: Data, duration: TimeInterval)
}

enum AccessoryRow {
    case tools, fonts, colors, highlight, ai
}

enum TextSizeChoice: CaseIterable {
    case small, medium, large

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 17
        case .large: return 30
        }
    }
}

// MARK: - Keyboard accessory (accordion) and dictation

extension CanvasScene {
    // MARK: Text accessory (accordion: one row expanded at a time)

    /// The block being edited, for showing its current style.
    private var editingBlock: TextBlock? {
        guard let id = editor.editingTextItemID,
              case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    @ViewBuilder var textAccessory: some View {
        switch accessoryRow {
        case .tools:
            Button("Aa") { accessoryRow = .fonts }
                .accessibilityLabel("Font and size")
                .accessibilityIdentifier("style.sizes")
            Button {
                accessoryRow = .colors
            } label: {
                Circle()
                    .fill(Palette.color(named: editingBlock?.colorName ?? "ink"))
                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                    .frame(width: 18, height: 18)
            }
            .accessibilityLabel("Text color")
            .accessibilityIdentifier("style.colors")
            Button {
                accessoryRow = .highlight
            } label: {
                Image(systemName: "character.textbox")
            }
            .accessibilityLabel("Text background")
            .accessibilityIdentifier("style.highlight")
            Button {
                if let id = editor.editingTextItemID, let block = editingBlock {
                    editor.setTextAlignment(itemID: id, to: block.alignment.next)
                }
            } label: {
                Image(systemName: (editingBlock?.alignment ?? .leading).symbol)
            }
            .accessibilityLabel("Alignment")
            .accessibilityValue((editingBlock?.alignment ?? .leading).rawValue)
            .accessibilityIdentifier("style.align")
            Button {
                accessoryRow = .ai
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel("Rewrite")
            .accessibilityIdentifier("style.ai")
            Button {
                toggleDictation()
            } label: {
                // A live mic reads as ACTIVE (filled, accent, pulsing) --
                // mic.badge.xmark said "microphone blocked" while it
                // actually meant "tap to finish".
                Image(systemName: dictating ? "mic.fill" : "mic")
                    .foregroundStyle(dictating ? Palette.forest : Palette.ink)
                    .symbolEffect(.pulse, isActive: dictating)
            }
            .accessibilityIdentifier("style.mic")
            if dictating {
                Text("Listening...")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.forest)
            } else if let dictationHint {
                Text(dictationHint)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Done") { endTextEditing() }
                .fontWeight(.semibold)
                .accessibilityIdentifier("keyboard.done")
        case .fonts:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(TextFace.choices, id: \.name) { face in
                        Button(face.label) {
                            if let id = editor.editingTextItemID {
                                editor.setTextFont(itemID: id, to: face.name)
                                remeasureEditedText(id)
                            }
                        }
                        .font(Font(TextFace.uiFont(name: face.name, size: 15)))
                        .fontWeight(editingBlock?.fontName == face.name ? .bold : .regular)
                        .accessibilityAddTraits(editingBlock?.fontName == face.name ? .isSelected : [])
                        .accessibilityIdentifier("style.font.\(face.label)")
                    }
                    Divider().frame(height: 18)
                    ForEach(TextSizeChoice.allCases, id: \.self) { choice in
                        Button(choice.label) {
                            if let id = editor.editingTextItemID {
                                editor.setTextPointSize(itemID: id, to: choice.pointSize)
                                remeasureEditedText(id)
                            }
                        }
                        .accessibilityIdentifier("style.size.\(choice.label)")
                    }
                }
            }
            Button("Back") { closeStyleRow() }
        case .colors:
            swatchRow(
                current: editingBlock?.colorName ?? "ink",
                idPrefix: "style.color",
                apply: { id, name, record in editor.setTextColorName(itemID: id, to: name, recordingUndo: record) }
            )
            Button("Back") { closeStyleRow() }
        case .highlight:
            Button {
                if let id = editor.editingTextItemID {
                    editor.setTextBackground(itemID: id, to: "")
                }
            } label: {
                Image(systemName: "nosign")
            }
            .accessibilityLabel("No background")
            .accessibilityAddTraits(editingBlock?.backgroundColorName.isEmpty ?? true ? .isSelected : [])
            .accessibilityIdentifier("style.highlight.none")
            swatchRow(
                current: editingBlock?.backgroundColorName ?? "",
                idPrefix: "style.highlight",
                apply: { id, name, record in editor.setTextBackground(itemID: id, to: name, recordingUndo: record) }
            )
            Button("Back") { closeStyleRow() }
        case .ai:
            ForEach(["Clean up", "Expand"], id: \.self) { action in
                Button(action) { runTextAI(action) }
            }
            Spacer()
            Button("Back") { closeStyleRow() }
        }
    }

    /// Quick swatches plus the system color picker (custom color with its
    /// built-in eyedropper -- handoff screens 14 and 20). A swatch tap is
    /// always one undo step; a picker drag is grouped by `pickerUndo`.
    private func swatchRow(
        current: String,
        idPrefix: String,
        apply: @escaping (CanvasItem.ID, String, Bool) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Palette.textSwatches, id: \.hex) { swatch in
                    Button {
                        if let id = editor.editingTextItemID { apply(id, swatch.hex, true) }
                        pickerUndo.reset()
                    } label: {
                        Circle()
                            .fill(Palette.color(named: swatch.hex))
                            .overlay(Circle().strokeBorder(
                                current == swatch.hex ? Palette.ink : Palette.hairline,
                                lineWidth: current == swatch.hex ? 2 : 1
                            ))
                            .frame(width: 22, height: 22)
                    }
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(current == swatch.hex ? .isSelected : [])
                    .accessibilityIdentifier("\(idPrefix).\(swatch.hex)")
                }
                ColorPicker(
                    "Custom color",
                    selection: Binding(
                        get: { Palette.color(named: current.isEmpty ? "ink" : current) },
                        set: { color in
                            // An unchanged value must not spend the drag's
                            // one undo step before the drag really starts.
                            guard let id = editor.editingTextItemID, color.hexName != current else { return }
                            let record = pickerUndo.shouldRecord(item: id, field: idPrefix)
                            apply(id, color.hexName, record)
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .accessibilityIdentifier("\(idPrefix).custom")
            }
        }
    }

    private func closeStyleRow() {
        accessoryRow = .tools
        pickerUndo.reset()
    }

    func endTextEditing() {
        editor.endEditingText()
        textFocus = nil
        closeStyleRow()
        dictationHint = nil
    }

    /// The keyboard's sparkle chips: transform the block being edited via
    /// the same Mira turn machinery (working state, receipt, revert).
    func runTextAI(_ action: String) {
        guard let id = editor.editingTextItemID else { return }
        editor.select(id)
        endTextEditing()
        mira.ask("\(action.lowercased()) the text", editor: editor)
    }

    /// Size and face changes re-measure the block so the box fits the type.
    func remeasureEditedText(_ id: CanvasItem.ID) {
        guard let item = editor.item(id), case .text(let block) = item.content else { return }
        editor.autosizeTextHeight(itemID: id, to: TextMeasure.blockHeight(
            text: block.text,
            pointSize: block.pointSize,
            fontName: block.fontName,
            width: item.size.width
        ))
    }

    /// Ends a dictation that lost its editing session (keyboard dismissed,
    /// editing finished): stop the mic quietly, keep nothing.
    func cancelDictationIfNeeded() {
        guard dictating else { return }
        let abandoned = recorder
        recorder = nil
        dictating = false
        Task { _ = try? await abandoned?.stop() }
    }

    /// Tap-to-toggle dictation: record, transcribe (:8005), append to the
    /// block being edited. The sound tool and dictation never share the
    /// recorder slot (guarded on both entry points).
    func toggleDictation() {
        if dictating {
            guard let recorder else {
                dictating = false
                return
            }
            self.recorder = nil
            Task {
                defer { dictating = false }
                // A silent return here looked like a dead feature: say why
                // nothing landed instead of swallowing it.
                guard let data = try? await recorder.stop(), !data.isEmpty else {
                    dictationHint = "I couldn't catch any words -- try again?"
                    return
                }
                guard let id = editor.editingTextItemID else {
                    dictationHint = "Tap a text block first, then dictate."
                    return
                }
                guard let transcript = try? await transcription.transcribe(
                    audio: data, filename: "dictation.m4a"
                ) else {
                    dictationHint = "Couldn't reach the transcriber -- try again?"
                    return
                }
                let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !words.isEmpty else {
                    dictationHint = "I couldn't catch any words -- try again?"
                    return
                }
                if case .text(let block) = editor.item(id)?.content {
                    let joined = block.text.isEmpty ? words : block.text + " " + words
                    editor.setText(itemID: id, to: joined)
                    // Grow the box to the new text like typing does, or the
                    // dictated words land clipped below the fold and read as
                    // "nothing happened."
                    if let width = editor.item(id)?.size.width {
                        editor.autosizeTextHeight(itemID: id, to: TextMeasure.blockHeight(
                            text: joined, pointSize: block.pointSize, fontName: block.fontName,
                            width: width))
                    }
                }
            }
        } else {
            guard recorder == nil else { return }
            dictationHint = nil
            let newRecorder = recorderFactory()
            recorder = newRecorder
            Task {
                do {
                    try await newRecorder.start()
                    dictating = true
                } catch {
                    recorder = nil
                    dictationHint = error.localizedDescription
                }
            }
        }
    }
}
