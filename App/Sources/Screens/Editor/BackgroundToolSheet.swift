import MiraNoteKit
import SwiftUI
import UIKit

/// The Background tool (handoff screen 05): a glass sheet laid over the
/// canvas card -- a live preview of the page, paper type, page color (five
/// swatches, Custom, Pick, a hex field), the eight curated sets and one-tap
/// layout. Every control applies to the page at once, one undo step each;
/// the composer below it ("Apply to this page") asks Mira to paint a
/// backdrop from words.
struct BackgroundToolSheet: View {
    @Bindable var editor: CanvasViewModel
    /// Sends a request through Mira's normal turn (working state, Stop,
    /// result sheet).
    var onAsk: (String) -> Void
    var onClose: () -> Void

    @State private var pickerUndo = PickerUndoGate()
    @State private var hexDraft = ""
    @FocusState private var hexFocused: Bool
    @State private var colorRequest: PageColorRequest?
    @State private var contentHeight: CGFloat?
    /// The picker gate keys drags by item; the page is one fixed key.
    private static let pageKey = UUID()

    /// The handoff's page colors (screen 05), stored as "#RRGGBB".
    static let pageSwatches: [(hex: String, name: String)] = [
        ("#F6F4E8", "Paper"), ("#F4E0D1", "Blush"), ("#D6E3D4", "Sage"),
        ("#D1E0F0", "Sky"), ("#E6D9F0", "Lilac")
    ]

    var body: some View {
        // The sheet hugs its 566 pt of content on the card; a card shorter
        // than that (or squeezed by the keyboard) scrolls it. One scroll
        // view throughout: swapping views would drop the hex field's focus.
        ScrollView(showsIndicators: false) {
            content
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { contentHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, height in contentHeight = height }
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: contentHeight ?? .infinity)
        .background(
            GlassSurface(
                shape: RoundedRectangle(cornerRadius: 30),
                tint: Palette.paper.opacity(0.5),
                shadowOpacity: 0.16,
                shadowRadius: 18,
                shadowY: 18
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .onAppear { hexDraft = shownHex }
        .onChange(of: editor.memory.pageColorName) { if !hexFocused { hexDraft = shownHex } }
        .sheet(item: $colorRequest, onDismiss: { pickerUndo.reset() }, content: customColorSheet)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            preview.padding(.top, 13)
            label("Page type").padding(.top, 13.5)
            paperRow.padding(.top, 5.5)
            label("Background color").padding(.top, 11.5)
            colorRow.padding(.top, 7.5)
            hexField.padding(.top, 2.5)
            curatedHeader.padding(.top, 13)
            curatedRow
            layoutButton.padding(.top, 7)
        }
        .padding(.top, 21)
        .padding(.bottom, 10)
        .padding(.horizontal, 23)
    }

    // MARK: Header and preview

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Background")
                .font(Sans.font(size: 20, weight: 700))
                .foregroundStyle(Palette.ink)
                .frame(height: 25)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("background.title")
            Text("Paper, color & curated type")
                .font(.miraComposer)
                .foregroundStyle(Palette.muted)
                .frame(height: 15)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Sans.font(size: 11, weight: 500))
            .foregroundStyle(Palette.ink)
            .frame(height: 15)
    }

    /// The page as it now looks: its backdrop and paper, its real title and
    /// first line in the faces and colors the page wears.
    private var preview: some View {
        let words = PreviewWords(editor: editor)
        return VStack(alignment: .leading, spacing: 0) {
            Text("PREVIEW COLOR  \u{00B7}  \(previewLabel)")
                .font(Sans.font(size: 10, weight: 600))
                .foregroundStyle(Palette.muted)
                .frame(height: 16)
                .padding(.top, 12)
                .accessibilityIdentifier("background.preview.color")
            Text(words.title)
                .font(words.titleFont)
                .foregroundStyle(words.titleColor)
                .frame(height: 25)
                .padding(.top, 9)
            Text(words.line)
                .font(words.lineFont)
                .foregroundStyle(words.lineColor)
                .frame(height: 15)
                .padding(.top, -2)
        }
        .lineLimit(1)
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 90, alignment: .topLeading)
        .background(PageBackdrop(memory: editor.memory))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.ink.opacity(0.1), lineWidth: 1))
    }

    private var previewLabel: String {
        if !editor.memory.backgroundFileName.isEmpty { return "PAINTED" }
        return editor.memory.pageColorName.isEmpty ? "DEFAULT" : editor.memory.pageColorName.uppercased()
    }

    // MARK: Paper

    private var paperRow: some View {
        HStack(spacing: 6) {
            ForEach(PaperKind.allCases, id: \.self) { kind in
                let selected = editor.memory.paper == kind
                Button {
                    editor.setPaper(kind)
                } label: {
                    PageTypeTile(kind: kind, selected: selected)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.rawValue.capitalized) paper")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("background.paper.\(kind.rawValue)")
            }
        }
    }

    // MARK: Color

    /// The page's own color when it shows: not while a painting covers it.
    private var pageColor: String {
        editor.memory.backgroundFileName.isEmpty ? editor.memory.pageColorName : ""
    }

    private var colorRow: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.pageSwatches.enumerated()), id: \.offset) { index, swatch in
                let chosen = pageColor == swatch.hex
                Button {
                    // The chosen dot, tapped again, gives the page back
                    // its default backdrop; the paper stays.
                    if chosen {
                        editor.resetPageBackground()
                    } else {
                        editor.setPageColor(swatch.hex)
                    }
                    pickerUndo.reset()
                } label: {
                    PageSwatch(color: Palette.color(named: swatch.hex), selected: chosen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityHint(chosen ? "Returns the page to its default backdrop" : "")
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("background.color.\(swatch.hex)")
                .offset(x: CGFloat(index) * 36)
            }
            colorTool("Custom", request: .custom) { CustomColorDot() }
                .offset(x: 186 - 8)
            colorTool("Pick", request: .pick) { PickColorDot() }
                .offset(x: 243 - 8)
        }
        .frame(height: 46.5, alignment: .topLeading)
    }

    /// A 28 pt dot with its label centered under it (44 wide, like the
    /// handoff's label box), offset 8 left of the dot's own x.
    private func colorTool<Dot: View>(
        _ title: String, request: PageColorRequest, @ViewBuilder dot: () -> Dot
    ) -> some View {
        Button {
            colorRequest = request
        } label: {
            VStack(spacing: 3.5) {
                dot()
                Text(title)
                    .font(Sans.font(size: 10, weight: 500))
                    .foregroundStyle(Palette.muted)
                    .frame(height: 15)
            }
            .frame(width: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(request == .custom ? "Custom page color" : "Pick a page color")
        .accessibilityIdentifier("background.color.\(request.rawValue)")
    }

    private var hexField: some View {
        TextField("", text: $hexDraft, prompt: Text("#RRGGBB").foregroundStyle(Palette.muted))
            .font(Sans.font(size: 10, weight: 500))
            .foregroundStyle(Palette.muted)
            .tint(Palette.forest)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
            .focused($hexFocused)
            .onSubmit(commitHex)
            .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
            .padding(.horizontal, 12)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BackgroundToolColors.rule, lineWidth: 1))
            )
            .accessibilityLabel("Page color hex")
            .accessibilityIdentifier("background.hex")
    }

    /// What the hex field shows when nobody is typing in it.
    private var shownHex: String { pageColor }

    private func commitHex() {
        if let hex = Self.normalizedHex(hexDraft), hex != pageColor {
            editor.setPageColor(hex)
            pickerUndo.reset()
        }
        hexDraft = shownHex
    }

    /// "e5d9f0", " #E5D9F0 " -> "#E5D9F0"; anything but six hex digits -> nil.
    static func normalizedHex(_ text: String) -> String? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits
    }

    // MARK: Custom color seam

    /// INTEGRATION SEAM. Custom and Pick open the shared `CustomColorSheet`
    /// (custom color + eyedropper, built by the text-editor stream). Until it
    /// lands, the system color picker -- which has its own eyedropper --
    /// stands in. Swapping is this one body; `applyPicked` keeps a drag to
    /// one undo step.
    private func customColorSheet(_ request: PageColorRequest) -> some View {
        SystemColorPickerSheet(
            initial: Palette.color(named: pageColor.isEmpty ? "#F6F4E8" : pageColor),
            onChange: applyPicked,
            onFinish: { colorRequest = nil }
        )
    }

    private func applyPicked(_ color: Color) {
        let hex = color.hexName
        guard hex != pageColor else { return }
        let record = pickerUndo.shouldRecord(item: Self.pageKey, field: "page")
        editor.setPageColor(hex, recordingUndo: record)
    }
}

extension BackgroundToolSheet {
    // MARK: Curated sets

    private var curatedHeader: some View {
        HStack(alignment: .top) {
            Text("Curated sets \u{00B7} \(CuratedSet.all.count)")
                .font(Sans.font(size: 11, weight: 600))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text("SWIPE \u{2192}")
                .font(Sans.font(size: 10, weight: 600))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
        }
        .frame(height: 18, alignment: .top)
    }

    private var curatedRow: some View {
        let worn = editor.wornCuratedSet()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CuratedSet.all) { set in
                    let look = CuratedSetLook.look(for: set)
                    Button {
                        editor.applyCuratedSet(set)
                        pickerUndo.reset()
                    } label: {
                        CuratedSetCard(set: set, worn: worn == set)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(look.displayLabel) and \(look.bodyLabel)")
                    .accessibilityAddTraits(worn == set ? .isSelected : [])
                    .accessibilityIdentifier("background.set.\(set.id)")
                }
            }
        }
        .frame(height: 102)
    }

    // MARK: One-tap layout

    /// One tap re-lays the page out through Mira's normal turn (Stop,
    /// result sheet, Revert), as the "Tidy the layout" chip does.
    private var layoutButton: some View {
        let enabled = editor.items.count >= 2
        return Button {
            onClose()
            onAsk(MiraCanvasCoordinator.tidyChip)
        } label: {
            HStack(spacing: 8) {
                Image("background.oneTap")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text("One-tap layout")
                    .font(Sans.font(size: 12, weight: 600))
            }
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11).fill(Palette.selectedTool))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier("background.layout")
    }
}

/// What the Custom and Pick dots ask the color sheet for.
enum PageColorRequest: String, Identifiable {
    case custom, pick
    var id: String { rawValue }
}
