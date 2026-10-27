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
    /// Custom and Pick open the shared custom color sheet (screens 14/20),
    /// which the scene lays over the dock so it can ride the keyboard.
    var onCustomColor: (PageColorRequest) -> Void
    /// Apply's painting is on its way (the sheet stays up until it lands).
    var painting = false
    /// Why Apply's painting did not come, while the sheet stays up.
    var notice: String?
    /// While Apply's words are typed the keyboard leaves the card too short
    /// for the sheet: it folds to its title and status line.
    var folded = false

    @State private var hexDraft = ""
    /// Words typed in the hex field and not committed yet.
    @State private var typingHex = false
    @FocusState private var hexFocused: Bool
    @State private var contentHeight: CGFloat?

    /// The handoff's page colors (screen 05), stored as "#RRGGBB".
    static let pageSwatches: [(hex: String, name: String)] = [
        ("#F6F4E8", "Paper"), ("#F4E0D1", "Blush"), ("#D6E3D4", "Sage"),
        ("#D1E0F0", "Sky"), ("#E6D9F0", "Lilac")
    ]

    /// The content's side inset inside the sheet (the curated row bleeds
    /// past it to the sheet's edge).
    private static let inset: CGFloat = 23

    var body: some View {
        // The sheet fills the card less its 8 pt margin, One-tap layout at
        // its foot; a card shorter than the content (a small phone) scrolls
        // it. Folded, it hugs its title. One scroll view throughout:
        // swapping views would drop the hex field's focus.
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                content
                    .frame(minHeight: folded ? nil : geo.size.height, alignment: .top)
                    .background(GeometryReader { inner in
                        Color.clear
                            .onAppear { contentHeight = inner.size.height }
                            .onChange(of: inner.size.height) { _, height in contentHeight = height }
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: folded ? contentHeight ?? .infinity : .infinity)
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
        // Apply closes the sheet with the hex field still focused: a typed
        // color is the user's pick all the same.
        .onDisappear { if typingHex { commitHex() } }
    }

    private var content: some View {
        // One rhythm: 16 between sections, 8 from a label to its control.
        VStack(alignment: .leading, spacing: 0) {
            header
            if !folded {
                preview.padding(.top, 14)
                label("Page type").padding(.top, 16)
                paperRow.padding(.top, 8)
                label("Background color").padding(.top, 16)
                // While Apply paints the color controls rest: a color set
                // now would wipe the paid painting when it lands.
                Group {
                    colorRow.padding(.top, 8)
                    hexField.padding(.top, 10)
                }
                .disabled(painting)
                .opacity(painting ? 0.45 : 1)
                curatedHeader.padding(.top, 16)
                curatedRow.padding(.top, 8)
                Spacer(minLength: 16)
                layoutButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 21)
        .padding(.bottom, folded ? 18 : 21)
        .padding(.horizontal, Self.inset)
    }

    // MARK: Header and preview

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Background")
                .font(Sans.font(size: 22, weight: 700))
                .foregroundStyle(Palette.ink)
                .frame(height: 25)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("background.title")
            if painting {
                Text("Painting a background for this page...")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.forest)
                    .frame(height: 15)
                    .accessibilityIdentifier("background.status")
            } else if let notice {
                Text(notice)
                    .font(.miraLabel)
                    .foregroundStyle(Color(hex: 0x8C4A3A))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("background.notice")
            } else {
                Text("Paper, color & curated type")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.muted)
                    .frame(height: 15)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(copy: text)
            .font(Sans.font(size: 13, weight: 500))
            .foregroundStyle(Palette.ink)
            .frame(height: 15)
    }

    /// The page as it now looks: its backdrop and paper, its real title and
    /// first line in the faces and colors the page wears.
    private var preview: some View {
        let words = PreviewWords(editor: editor)
        return VStack(alignment: .leading, spacing: 0) {
            Text("PREVIEW COLOR  \u{00B7}  \(previewLabel)")
                .font(Sans.font(size: 12, weight: 600))
                .foregroundStyle(Palette.muted)
                .frame(height: 16)
                .padding(.top, 12)
                .accessibilityIdentifier("background.preview.color")
            Text(words.title)
                .font(words.titleFont)
                .foregroundStyle(words.titleColor)
                .lineLimit(1)
                .padding(.top, 10)
            Text(words.line)
                .font(words.lineFont)
                .foregroundStyle(words.lineColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 17)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PageBackdrop(memory: editor.memory))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.ink.opacity(0.1), lineWidth: 1))
    }

    private var previewLabel: String {
        if !editor.memory.backgroundFileName.isEmpty { return String(appCopy: "PAINTED") }
        return editor.memory.pageColorName.isEmpty ? String(appCopy: "DEFAULT") : editor.memory.pageColorName.uppercased()
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
                .accessibilityLabel(String(appCopy: "\(kind.title) paper"))
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

    /// The five page colors, then Custom and Pick: seven 28 pt dots on one
    /// line, first and last on the content's edges, evenly spaced. The two
    /// tools carry their names for VoiceOver; their glyphs say it on screen.
    private var colorRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.pageSwatches, id: \.hex) { swatch in
                swatchButton(swatch)
                Spacer(minLength: 4)
            }
            colorTool(request: .custom) { CustomColorDot() }
            Spacer(minLength: 4)
            colorTool(request: .pick) { PickColorDot() }
        }
        .frame(height: 28)
    }

    private func swatchButton(_ swatch: (hex: String, name: String)) -> some View {
        let chosen = pageColor == swatch.hex
        return Button {
            // The chosen dot, tapped again, gives the page back its default
            // backdrop; the paper stays.
            if chosen {
                editor.resetPageBackground()
            } else {
                editor.setPageColor(swatch.hex)
            }
        } label: {
            PageSwatch(color: Palette.color(named: swatch.hex), selected: chosen)
                .dotHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(copy: swatch.name))
        .accessibilityHint(chosen ? Text("Returns the page to its default backdrop") : Text(verbatim: ""))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("background.color.\(swatch.hex)")
    }

    private func colorTool<Dot: View>(request: PageColorRequest, @ViewBuilder dot: () -> Dot) -> some View {
        Button {
            hexFocused = false
            onCustomColor(request)
        } label: {
            dot().dotHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(request == .custom ? Text("Custom page color") : Text("Pick a page color"))
        .accessibilityIdentifier("background.color.\(request.rawValue)")
    }

    private var hexField: some View {
        TextField("", text: $hexDraft, prompt: Text("#RRGGBB").foregroundStyle(Palette.muted))
            .font(Sans.font(size: 12, weight: 500))
            .foregroundStyle(Palette.muted)
            .tint(Palette.forest)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
            .focused($hexFocused)
            .onSubmit(commitHex)
            .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
            .onChange(of: hexDraft) { _, draft in if hexFocused, draft != shownHex { typingHex = true } }
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
        typingHex = false
        if let hex = Self.normalizedHex(hexDraft), hex != pageColor {
            editor.setPageColor(hex)
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
}

extension BackgroundToolSheet {
    // MARK: Curated sets

    private var curatedHeader: some View {
        HStack(alignment: .top) {
            Text("Curated sets \u{00B7} \(CuratedSet.all.count)")
                .font(Sans.font(size: 13, weight: 600))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text("SWIPE \u{2192}")
                .font(Sans.font(size: 12, weight: 600))
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
                    } label: {
                        CuratedSetCard(set: set, worn: worn == set)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(look.displayLabel) and \(look.bodyLabel)")
                    .accessibilityAddTraits(worn == set ? .isSelected : [])
                    .accessibilityIdentifier("background.set.\(set.id)")
                }
            }
            // Starts on the content's edge, scrolls out to the sheet's.
            .padding(.horizontal, Self.inset)
        }
        .padding(.horizontal, -Self.inset)
        .frame(height: 102)
    }

    // MARK: One-tap layout

    /// One tap re-lays the page out through Mira's normal turn (Stop,
    /// result sheet, Revert), as the "Tidy the layout" chip does.
    private var layoutButton: some View {
        // Mira is busy painting: the tidy would be dropped.
        let enabled = editor.items.count >= 2 && !painting
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
                    .font(Sans.font(size: 14, weight: 600))
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

private extension View {
    /// A 28 pt color dot taps as a 44 x 44 box without moving the row.
    func dotHitTarget() -> some View {
        padding(8)
            .contentShape(Rectangle())
            .padding(-8)
    }
}

/// What the Custom and Pick dots ask the color sheet for.
enum PageColorRequest: String, Identifiable {
    case custom, pick
    var id: String { rawValue }
}
