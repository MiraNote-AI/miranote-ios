import MiraNoteKit
import SwiftUI

/// The Background tool (handoff screen 05): paper ruling, a page color, a
/// mood Mira paints, curated font sets, and one-tap layout.
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

    /// The handoff's curated type (screen 05): a display face for titles and
    /// a body face for the rest, drawn from the faces TextFace offers ("" is
    /// the default serif display).
    static let fontSets: [FontSet] = [
        FontSet(name: "Classic", display: "Didot", body: "Optima", swatch: 0xC9B295),
        FontSet(name: "Editorial", display: "", body: "Josefin Sans", swatch: 0xF1DFD0),
        FontSet(name: "Modern", display: "Futura", body: "Helvetica Neue", swatch: 0x24382D, isDark: true),
        FontSet(name: "Soft", display: "Josefin Sans", body: "Optima", swatch: 0xE5D9F0),
    ]

    private var onDefault: Bool {
        editor.memory.pageColorName.isEmpty && editor.memory.backgroundFileName.isEmpty
    }

    var body: some View {
        ContextCard(title: "Background", subtitle: "Paper, color, a mood, and curated type.") {
            VStack(alignment: .leading, spacing: 12) {
                paperRow
                colorRow
                moodRow
                fontSetRow
                layoutButton
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

    private var textBlocks: [TextBlock] {
        editor.items.compactMap {
            if case .text(let block) = $0.content { return block }
            return nil
        }
    }

    /// A set reads as chosen when every text block already wears it.
    private func isWorn(_ set: FontSet) -> Bool {
        !textBlocks.isEmpty && textBlocks.allSatisfy {
            $0.fontName == ($0.pointSize >= CanvasViewModel.displayPointSize ? set.display : set.body)
        }
    }

    private var fontSetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.fontSets, id: \.name) { set in
                    let worn = isWorn(set)
                    Button {
                        editor.applyFontSet(display: set.display, body: set.body)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aa")
                                .font(Font(TextFace.uiFont(name: set.display, size: 26)))
                            Text(set.name)
                                .font(Font(TextFace.uiFont(name: set.body, size: 12)))
                        }
                        .foregroundStyle(set.isDark ? Palette.onInk : Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(width: 104, height: 72, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: set.swatch))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                                    worn ? Palette.ink : Palette.hairline, lineWidth: worn ? 2 : 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(textBlocks.isEmpty)
                    .accessibilityLabel("\(set.name) type")
                    .accessibilityAddTraits(worn ? .isSelected : [])
                    .accessibilityIdentifier("background.fontSet.\(set.name)")
                }
            }
        }
    }

    /// One tap re-lays the page out through Mira's normal turn (Stop,
    /// receipt, Revert), as the "Tidy the layout" chip does.
    private var layoutButton: some View {
        Button {
            onClose()
            onAsk(MiraCanvasCoordinator.tidyChip)
        } label: {
            Label("One-tap layout", systemImage: "sparkles")
                .font(Sans.font(size: 14, weight: 600))
                .foregroundStyle(Palette.onInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 16).fill(Palette.selectedTool))
        }
        .buttonStyle(.plain)
        .disabled(editor.items.count < 2)
        .opacity(editor.items.count < 2 ? 0.45 : 1)
        .accessibilityIdentifier("background.layout")
    }
}

/// One curated pairing in the Background tool.
struct FontSet {
    let name: String
    let display: String
    let body: String
    let swatch: UInt32
    /// The swatch is dark enough to take light lettering.
    var isDark = false
}
