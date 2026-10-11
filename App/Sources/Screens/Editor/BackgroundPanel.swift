import MiraNoteKit
import SwiftUI

/// The Background tool (handoff screen 05): paper ruling, a page color, or a
/// mood Mira paints. Curated font sets and one-tap layout from the handoff
/// are later work.
struct BackgroundPanel: View {
    @Bindable var editor: CanvasViewModel
    /// Sends a request through the Mira bar's normal turn (working state,
    /// Stop, Keep/Revert receipt).
    var onAsk: (String) -> Void
    var onClose: () -> Void

    @State private var pickerUndo = PickerUndoGate()
    /// The picker gate keys drags by item; the page is one fixed key.
    private static let pageKey = UUID()

    /// Each mood becomes a sentence Mira already routes as a background ask
    /// (pinned by BackgroundMoodRoutingTests).
    static let moods = ["Sunset glow", "Soft paper", "Night sky", "Garden"]

    static func ask(for mood: String) -> String {
        "Make the background \(mood.lowercased())"
    }

    /// The handoff's page-color dots (screen 05), stored as "#RRGGBB".
    static let pageSwatches: [(hex: String, name: String)] = [
        ("#F3EFE3", "Cream"), ("#F1DFD0", "Peach"), ("#D9E3D3", "Sage"),
        ("#D8E3EF", "Sky"), ("#E5D9F0", "Lilac"),
    ]

    private var onDefault: Bool {
        editor.memory.pageColorName.isEmpty && editor.memory.backgroundFileName.isEmpty
    }

    var body: some View {
        ContextCard(title: "Background", subtitle: "Paper, color, or a mood Mira paints.") {
            VStack(alignment: .leading, spacing: 12) {
                paperRow
                colorRow
                moodRow
            }
        }
    }

    private var paperRow: some View {
        HStack(spacing: 8) {
            ForEach(PaperKind.allCases, id: \.self) { kind in
                Button {
                    editor.setPaper(kind)
                } label: {
                    Chip(text: kind.rawValue.capitalized, selected: editor.memory.paper == kind)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(editor.memory.paper == kind ? .isSelected : [])
                .accessibilityIdentifier("background.paper.\(kind.rawValue)")
            }
            Spacer(minLength: 0)
        }
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    editor.resetPageBackground()
                    pickerUndo.reset()
                } label: {
                    Chip(text: "Default", selected: onDefault, fillWhenSelected: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("background.default")
                .accessibilityAddTraits(onDefault ? .isSelected : [])

                ForEach(Self.pageSwatches, id: \.hex) { swatch in
                    let chosen = editor.memory.pageColorName == swatch.hex
                    Button {
                        editor.setPageColor(swatch.hex)
                        pickerUndo.reset()
                    } label: {
                        Circle()
                            .fill(Palette.color(named: swatch.hex))
                            .overlay(Circle().strokeBorder(
                                chosen ? Palette.ink : Palette.hairline, lineWidth: chosen ? 2 : 1))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("background.color.\(swatch.hex)")
                }

                ColorPicker(
                    "Custom page color",
                    selection: Binding(
                        get: {
                            Palette.color(named: editor.memory.pageColorName.isEmpty
                                          ? "#F3EFE3" : editor.memory.pageColorName)
                        },
                        set: { color in
                            let record = pickerUndo.shouldRecord(item: Self.pageKey, field: "page")
                            editor.setPageColor(color.hexName, recordingUndo: record)
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .accessibilityIdentifier("background.color.custom")
            }
        }
    }

    private var moodRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.moods, id: \.self) { mood in
                    Button {
                        onClose()
                        onAsk(Self.ask(for: mood))
                    } label: {
                        Chip(text: mood, systemImage: "sparkles")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("background.mood.\(mood)")
                }
            }
        }
    }
}
