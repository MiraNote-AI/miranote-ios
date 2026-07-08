import Foundation
import SwiftUI

// Shared state shapes for CanvasScene's bottom cluster.

enum RecorderState {
    case idle
    case recording(start: Date)
    case review(data: Data, duration: TimeInterval)
}

enum AccessoryRow {
    case tools, sizes, colors, ai
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

    @ViewBuilder var textAccessory: some View {
        switch accessoryRow {
        case .tools:
            Button("Aa") { accessoryRow = .sizes }
                .accessibilityIdentifier("style.sizes")
            Button {
                accessoryRow = .colors
            } label: {
                Circle().fill(Palette.forest).frame(width: 16, height: 16)
            }
            .accessibilityIdentifier("style.colors")
            Button {
                accessoryRow = .ai
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityIdentifier("style.ai")
            Button {
                toggleDictation()
            } label: {
                Image(systemName: dictating ? "mic.badge.xmark" : "mic")
            }
            .accessibilityIdentifier("style.mic")
            Spacer()
            Button("Done") { endTextEditing() }
                .fontWeight(.semibold)
                .accessibilityIdentifier("keyboard.done")
        case .sizes:
            ForEach(TextSizeChoice.allCases, id: \.self) { choice in
                Button(choice.label) {
                    if let id = editor.editingTextItemID {
                        editor.setTextPointSize(itemID: id, to: choice.pointSize)
                    }
                }
            }
            Spacer()
            Button("Back") { accessoryRow = .tools }
        case .colors:
            ForEach(["ink", "forest", "taupe", "tan", "textSecondary"], id: \.self) { name in
                Button {
                    if let id = editor.editingTextItemID {
                        editor.setTextColorName(itemID: id, to: name)
                    }
                } label: {
                    Circle().fill(Palette.color(named: name)).frame(width: 18, height: 18)
                }
            }
            Spacer()
            Button("Back") { accessoryRow = .tools }
        case .ai:
            ForEach(["Polish", "Expand", "Tighten"], id: \.self) { action in
                Button(action) { runTextAI(action) }
            }
            Spacer()
            Button("Back") { accessoryRow = .tools }
        }
    }

    func endTextEditing() {
        editor.endEditingText()
        textFocus = nil
        accessoryRow = .tools
    }

    /// The keyboard's sparkle chips: transform the block being edited via
    /// the same Mira turn machinery (working state, receipt, revert).
    func runTextAI(_ action: String) {
        guard let id = editor.editingTextItemID else { return }
        editor.select(id)
        endTextEditing()
        mira.ask("\(action.lowercased()) the text", editor: editor)
    }

    /// Tap-to-toggle dictation: record, transcribe (:8000), append to the
    /// block being edited.
    func toggleDictation() {
        if dictating {
            guard let recorder else {
                dictating = false
                return
            }
            self.recorder = nil
            Task {
                defer { dictating = false }
                guard let data = try? await recorder.stop(), !data.isEmpty,
                      let id = editor.editingTextItemID,
                      let transcript = try? await transcription.transcribe(audio: data, filename: "dictation.m4a")
                else { return }
                if case .text(let block) = editor.item(id)?.content {
                    let joined = block.text.isEmpty ? transcript : block.text + " " + transcript
                    editor.setText(itemID: id, to: joined)
                }
            }
        } else {
            let newRecorder = recorderFactory()
            recorder = newRecorder
            Task {
                do {
                    try await newRecorder.start()
                    dictating = true
                } catch {
                    recorder = nil
                    recorderNotice = error.localizedDescription
                }
            }
        }
    }
}
