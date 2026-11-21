import MiraNoteKit
import SwiftUI

// The text editor's accessory (handoff screens 11-20, #205), bottom to top
// above the keyboard: the Mira chat box with its mic, Back and the
// persistent five-icon tool bar, and the active tool's secondary row. Pure
// views: CanvasScene owns the state and passes it in.

/// The five text tools, in the tool bar's order.
enum TextTool: CaseIterable {
    case font, color, ai, align, background

    /// Whether the tool opens a row above the tool bar (align does not).
    var hasRow: Bool { self != .align }

    /// The row's gap above the tool bar, as drawn.
    var rowGap: CGFloat {
        switch self {
        case .font: return 8.7
        case .color: return 11.8
        case .ai, .background, .align: return 7.8
        }
    }
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

    /// M is the handoff's new-block size.
    var pointSize: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return TextFace.newBlockSize
        case .large: return 30
        }
    }
}

private enum Tokens {
    static let forest = Color(hex: 0x293322)
    static let deepForest = Color(hex: 0x24382D)
    static let warmWhite = Color(hex: 0xFFFDF8)
    static let linen = Color(hex: 0xF1EBDD)
    static let barRim = Color(hex: 0xDBCEBD)
    static let chipRim = Color(hex: 0xD6C8B5)
    static let rosewood = Color(hex: 0x9B7A70)
    /// The custom chip's conic run (screen 18), from 90 degrees.
    static let conic: [Color] = [
        0x24382D, 0x484B3D, 0x6C5D4D, 0x90705D, 0xB4826D, 0xD3B7A5, 0xF1EBDD,
        0xD8C6BE, 0xBEA1A0, 0xA57B81, 0x8B5662, 0x584748, 0x3E403A, 0x24382D,
    ].map { Color(hex: $0) }
}

// MARK: - Tool bar

/// "MiraNote text icon toolbar": 36 tall, a frosted glass capsule. Exactly one
/// tool is active and drawn inverted (light).
struct TextToolBar: View {
    let active: TextTool
    let alignment: TextAlign
    let onSelect: (TextTool) -> Void

    /// The block's alignment as VoiceOver reads it, in the app's language.
    private static func spoken(_ alignment: TextAlign) -> String {
        switch alignment {
        case .leading: return String(appCopy: "Left")
        case .center: return String(appCopy: "Centered")
        case .trailing: return String(appCopy: "Right")
        }
    }

    /// Tool centers as fractions of the drawn 342 pt bar.
    private static let centers: [TextTool: CGFloat] = [
        .font: 23.5 / 342, .color: 95.2 / 342, .ai: 168.8 / 342, .align: 245 / 342, .background: 309.9 / 342,
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(TextTool.allCases, id: \.self) { tool in
                Button {
                    onSelect(tool)
                } label: {
                    glyph(tool, active: tool == active)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(tool))
                .accessibilityValue(tool == .align ? Self.spoken(alignment) : "")
                .accessibilityAddTraits(tool == active ? .isSelected : [])
                .accessibilityIdentifier(identifier(tool))
                .position(x: geo.size.width * (Self.centers[tool] ?? 0), y: geo.size.height / 2)
            }
        }
        .frame(height: 36)
        // The page under it is sharp now (#205): the glass blurs it itself.
        .background(TextGlass(shape: Capsule()))
    }

    @ViewBuilder private func glyph(_ tool: TextTool, active: Bool) -> some View {
        let ink = active ? Tokens.warmWhite : Tokens.forest
        switch tool {
        case .font:
            Text("Aa")
                .font(Sans.font(size: 16, weight: 700))
                .foregroundStyle(active ? Tokens.forest : .white)
                .frame(width: 29, height: 17)
                .background(Capsule().fill(active ? Tokens.warmWhite : Tokens.forest))
        case .color:
            Image(active ? "text.tool.palette.active" : "text.tool.palette")
                .resizable()
                .frame(width: 23.8, height: 23.8)
        case .ai:
            Image("text.tool.ai")
                .renderingMode(.template)
                .resizable()
                .frame(width: 27, height: 27)
                .foregroundStyle(ink)
        case .align:
            AlignGlyph(alignment: alignment, color: ink)
        case .background:
            Image("text.tool.background")
                .renderingMode(.template)
                .resizable()
                .frame(width: 23.8, height: 23.8)
                .foregroundStyle(ink)
        }
    }

    private func label(_ tool: TextTool) -> String {
        switch tool {
        case .font: return String(appCopy: "Font and size")
        case .color: return String(appCopy: "Text color")
        case .ai: return String(appCopy: "Rewrite")
        case .align: return String(appCopy: "Alignment")
        case .background: return String(appCopy: "Text background")
        }
    }

    /// The identifiers the accessory's controls had before the redesign.
    private func identifier(_ tool: TextTool) -> String {
        switch tool {
        case .font: return "style.sizes"
        case .color: return "style.colors"
        case .ai: return "style.ai"
        case .align: return "style.align"
        case .background: return "style.highlight"
        }
    }
}

/// The drawn 23% warm white glass of the text chrome, over its own blur.
private struct TextGlass<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        GlassSurface(shape: shape, tint: Tokens.warmWhite.opacity(0.23), rim: Tokens.barRim,
                     highlight: false, shadowOpacity: 0.08, shadowRadius: 3, shadowY: 5.3)
    }
}

/// The leading Back key of the text row (R1A): ends the writing, as a tap
/// on the page or Esc on a hardware keyboard (`WritingEscape`) does. A glass circle as tall as
/// the tool bar beside it.
struct TextBackKey: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            Image("nav.back")
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(Tokens.forest)
                .frame(width: 36, height: 36)
                .background(TextGlass(shape: Circle()))
                // 36 drawn, 44 to the finger.
                .padding(4)
                .contentShape(Rectangle())
                .padding(-4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("keyboard.done")
    }
}

/// The Mira chat box while words are written (T1, T2): the composer's glass
/// reading "Ask Mira to refine...". Its trailing button is the mic while
/// the box is empty, Go once there are words (F7A). The mic dictates into
/// the block (D2A, F8A) -- hold to talk, or tap to start and tap again to
/// end; while it is live the box shows a waveform and "Listening...". Go
/// asks Mira to rewrite the block (F6B).
struct WritingChatBox: View {
    @Binding var ask: String
    var focus: FocusState<Bool>.Binding
    let listening: Bool
    /// The live take's recorder, for the waveform.
    let recorder: AudioRecording?
    /// What the mic is doing or why nothing landed, for VoiceOver and tests.
    let status: String
    /// The block has words for Mira to rewrite.
    let canGo: Bool
    /// Mira is rewriting the block as asked.
    let asking: Bool
    var onGo: () -> Void
    var onPress: () -> Void
    var onRelease: () -> Void
    var onCancel: () -> Void
    /// Starts or ends the take in one activation (assistive technologies).
    var onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasWords: Bool { !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            if listening, let recorder {
                LiveWaveform(recorder: recorder, tint: Tokens.forest, scale: 0.5)
                Text(copy: "Listening...")
                    .font(.miraComposer)
                    .foregroundStyle(Tokens.forest)
                    .lineLimit(1)
                    // The mic's value says so.
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            } else {
                // The block's kind of field, so the block's dark keyboard
                // stays dark as the caret moves here (#162: never swapped).
                // One line: Return sends, as Go does, and keeps the caret.
                TextField("", text: $ask, prompt: Text(copy: "Ask Mira to refine...").foregroundStyle(Palette.muted),
                          axis: .vertical)
                    .lineLimit(1)
                    .font(.miraComposer)
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.forest)
                    .submitLabel(.go)
                    .focused(focus)
                    .onChange(of: ask) { _, words in
                        guard words.contains("\n") else { return }
                        ask = words.replacingOccurrences(of: "\n", with: "")
                        if hasWords, canGo, !asking { onGo() }
                    }
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel(Text(copy: "Ask Mira to refine..."))
                    .accessibilityIdentifier("writing.ask")
            }
            if hasWords, !listening {
                go
            } else {
                mic
            }
        }
        .padding(.leading, 17)
        .padding(.trailing, 10)
        .frame(height: 54)
        .background(GlassCapsule())
    }

    /// The composer's ink Go pill; a spinner while Mira rewrites.
    private var go: some View {
        Button(action: onGo) {
            ZStack {
                if asking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.onInk)
                } else {
                    Text(copy: "Go")
                        .font(.miraComposerAction)
                        .foregroundStyle(Palette.onInk)
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 52)
            .frame(height: 34)
            .background(Capsule().fill(Palette.ink))
            .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .disabled(!canGo || asking)
        // As the Polish row with nothing to rewrite.
        .opacity(canGo ? 1 : 0.6)
        .accessibilityLabel(Text(copy: "Go"))
        .accessibilityIdentifier("writing.go")
    }

    private var mic: some View {
        Image("mira.dictation.mic")
            .renderingMode(.template)
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundStyle(Palette.onInk)
            .frame(width: 34, height: 34)
            .background(Circle().fill(listening ? Tokens.forest : Palette.ink))
            // Only the pulse repeats, never the fill; under Reduce Motion
            // the forest fill alone says it is live.
            .animation(listening ? .easeInOut(duration: 0.6).repeatForever() : .default) {
                $0.scaleEffect(listening && !reduceMotion ? 1.1 : 1)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .holdToTalk(onPress: onPress, onRelease: onRelease, onCancel: onCancel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mira Dictation")
            .accessibilityValue(status)
            .accessibilityHint(listening ? Text("Ends the dictation.") : Text("Hold to talk, or tap to start."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onToggle() }
            .accessibilityIdentifier("style.mic")
    }
}

/// The align tool drawn as the handoff's three rounded bars, mirroring the
/// block's alignment (screens 16-17; trailing by extension, as 11 shows).
struct AlignGlyph: View {
    let alignment: TextAlign
    let color: Color

    var body: some View {
        let widths: [CGFloat] = alignment == .center ? [21.8, 13, 22] : [21.8, 17.9, 10]
        let anchor: HorizontalAlignment = switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        VStack(alignment: anchor, spacing: 4.3) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                RoundedRectangle(cornerRadius: 1.323)
                    .fill(color)
                    .frame(width: width, height: index == 2 ? 3 : 2.645)
            }
        }
        .frame(width: 22, height: 17, alignment: Alignment(horizontal: anchor, vertical: .center))
    }
}

// MARK: - Font row

/// "MiraNote font carousel": 65x35 chips, each name in its own face, the
/// selected one forest. S/M/L follow as trailing chips (not drawn; kept).
struct FontChipRow: View {
    let fontName: String
    let pointSize: CGFloat
    /// On its way up with the keyboard: a still copy of the chips stands in,
    /// scrolled where the row is (#162: the scroll view does not ride the
    /// tools' slide; it stayed behind, split from the tool bar).
    var riding = false
    let onFont: (String) -> Void
    let onSize: (TextSizeChoice) -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                chips
            }
            .padding(.vertical, -8)
            .onAppear { proxy.scrollTo(fontName, anchor: .center) }
        }
        .opacity(riding ? 0 : 1)
        .allowsHitTesting(!riding)
        .overlay {
            if riding {
                GeometryReader { proxy in
                    chips
                        .fixedSize()
                        .offset(x: -scrolled(in: proxy.size.width))
                        .frame(width: proxy.size.width, alignment: .leading)
                        // The scroll view's bounds: its width, 8 past the chips.
                        .clipped()
                        .padding(.vertical, -8)
                }
                // Its chips take taps as the row's do, and the gaps between
                // them too, so no tap falls through to the page and ends
                // the writing.
                .contentShape(Rectangle())
                .accessibilityHidden(true)
            }
        }
        .frame(height: 35)
    }

    /// Where `scrollTo(fontName, anchor: .center)` leaves the row: the
    /// selected chip centered, held within the chips' run.
    private func scrolled(in width: CGFloat) -> CGFloat {
        let faces = CGFloat(TextFace.choices.count), sizes = CGFloat(TextSizeChoice.allCases.count)
        // Insets, chips, the rule with its 3 + 3, sizes, a gap between each.
        let run = Self.inset * 2 + faces * Self.faceWidth + (Self.rule + Self.rulePad * 2) + sizes * Self.sizeWidth
            + (faces + sizes) * Self.gap
        guard let index = TextFace.choices.firstIndex(where: { $0.name == fontName }) else { return 0 }
        let center = Self.inset + CGFloat(index) * (Self.faceWidth + Self.gap) + Self.faceWidth / 2
        let offset = min(max(center - width / 2, 0), max(run - width, 0))
        // On the pixel the scroll view lands on, so the swap moves nothing.
        return (offset * displayScale).rounded() / displayScale
    }

    // The chips' sizes, shared by the row and the stand-in's offset.
    private static let inset: CGFloat = 17
    private static let gap: CGFloat = 6
    private static let faceWidth: CGFloat = 65
    private static let sizeWidth: CGFloat = 44
    private static let rule: CGFloat = 1
    private static let rulePad: CGFloat = 3

    private var chips: some View {
        HStack(spacing: Self.gap) {
            ForEach(TextFace.choices, id: \.name) { face in
                let selected = face.name == fontName
                Button { onFont(face.name) } label: {
                    // Face names have no entry and show as given;
                    // "Classic" is copy.
                    Text(copy: face.label)
                        .font(Font(TextFace.uiFont(name: face.name, size: TextScale.scaled(14.5), weight: 500)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: Self.faceWidth - 6)
                        .foregroundStyle(selected ? .white : Tokens.forest)
                        .frame(width: Self.faceWidth, height: 35)
                        .background(FontChipBackground(selected: selected))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("style.font.\(face.label)")
                .id(face.name)
            }
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: Self.rule, height: 20)
                .padding(.horizontal, Self.rulePad)
            ForEach(TextSizeChoice.allCases, id: \.self) { choice in
                let selected = abs(choice.pointSize - pointSize) < 0.5
                Button { onSize(choice) } label: {
                    Text(choice.label)
                        .font(Sans.font(size: 16, weight: 700))
                        .foregroundStyle(selected ? .white : Tokens.forest)
                        .frame(width: Self.sizeWidth, height: 35)
                        .background(FontChipBackground(selected: selected))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Size \(choice.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("style.size.\(choice.label)")
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 8)
    }
}

private struct FontChipBackground: View {
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10.715)
        if selected {
            shape.fill(Tokens.forest)
                .shadow(color: Tokens.forest.opacity(0.12), radius: 5.7, y: 5)
        } else {
            shape.fill(Tokens.warmWhite.opacity(0.94))
                .overlay(shape.strokeBorder(Tokens.chipRim, lineWidth: 0.63))
                .shadow(color: Palette.ink.opacity(0.05), radius: 3.8, y: 2.5)
        }
    }
}

// MARK: - Color row

/// "Secondary selector" (screen 12): 30 pt swatches in 44 pt cells, the
/// picked one ringed with a check, then the custom disc. A custom color
/// already on the block fills the disc.
struct ColorSwatchRow: View {
    /// The block's color as stored.
    let current: String
    /// True when `current` came from the custom sheet.
    let isCustom: Bool
    let onSwatch: (String) -> Void
    let onCustom: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Palette.textSwatches, id: \.hex) { swatch in
                let selected = swatch.hex == current
                Button { onSwatch(swatch.hex) } label: {
                    SwatchDisc(color: Palette.color(named: swatch.hex), selected: selected,
                               darkMark: !RowColor.isDark(swatch.hex))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(copy: swatch.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("style.color.\(swatch.hex)")
            }
            Button(action: onCustom) {
                ZStack {
                    if isCustom {
                        SwatchDisc(color: Palette.color(named: current), selected: true,
                                   darkMark: !RowColor.isDark(current))
                    } else {
                        Circle()
                            .fill(AngularGradient(colors: Tokens.conic, center: .center, angle: .degrees(90)))
                            .frame(width: 30, height: 30)
                            .overlay(PlusMark(size: 12, thickness: 3))
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom color")
            .accessibilityAddTraits(isCustom ? .isSelected : [])
            .accessibilityIdentifier("style.color.custom")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 35)
    }
}

private struct SwatchDisc: View {
    let color: Color
    let selected: Bool
    /// A forest check on light colors, white on dark ones.
    let darkMark: Bool

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Tokens.rosewood.opacity(0.7), lineWidth: 1))
            .overlay {
                if selected {
                    Circle().strokeBorder(Tokens.deepForest.opacity(0.9), lineWidth: 1.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(darkMark ? Tokens.forest : .white)
                }
            }
            .frame(width: 30, height: 30)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// The custom chips' "+": two bars, linen with a faint forest rim.
private struct PlusMark: View {
    let size: CGFloat
    let thickness: CGFloat

    var body: some View {
        ZStack {
            bar.frame(width: size, height: thickness)
            bar.frame(width: thickness, height: size)
        }
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Tokens.linen)
            .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Tokens.deepForest.opacity(0.35), lineWidth: 0.5))
    }
}

enum RowColor {
    /// Relative luminance under 0.4: the check and labels go white.
    static func isDark(_ name: String) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Palette.color(named: name)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.4
    }
}

// MARK: - AI row

/// The AI rewrite selector (screen 15): Original / Clean up / Expand as a
/// segmented glass control. The chip of the version on the canvas is
/// forest; one being fetched spins.
struct RewriteRow: View {
    /// nil while the rewrite asked for in the chat box is shown (H3A).
    let selected: TextRewriteSession.Choice?
    let pending: TextRewriteSession.Choice?
    let enabled: Bool
    let onSelect: (TextRewriteSession.Choice) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TextRewriteSession.Choice.allCases, id: \.self) { choice in
                let on = choice == selected
                Button { onSelect(choice) } label: {
                    ZStack {
                        if pending == choice {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Tokens.deepForest)
                        } else {
                            Text(title(choice))
                                .font(Sans.font(size: 14, weight: 500))
                                .foregroundStyle(on ? Tokens.linen : Tokens.deepForest)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        Capsule()
                            .fill(on ? Tokens.deepForest : Color(hex: 0xDCCFC0))
                            .overlay(Capsule().strokeBorder(on ? Tokens.deepForest : Tokens.rosewood, lineWidth: 1))
                    )
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .padding(.vertical, -7)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("style.ai.\(choice.rawValue)")
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Tokens.warmWhite.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tokens.barRim, lineWidth: 0.66))
        )
        .opacity(enabled ? 1 : 0.6)
    }

    private func title(_ choice: TextRewriteSession.Choice) -> String {
        switch choice {
        case .original: return String(appCopy: "Original text")
        case .clean: return String(appCopy: "Clean up")
        case .expand: return String(appCopy: "Expand")
        }
    }
}

// MARK: - Text background row

/// The text-background chips (screen 18): none (outlined), Ink, Highlight
/// and the custom chip, each previewing "Aa" on its fill.
struct TextBackgroundRow: View {
    /// The block's background as stored ("" for none).
    let current: String
    let isCustom: Bool
    let onPick: (String) -> Void
    let onCustom: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            chip(fill: nil, selected: current.isEmpty, id: "none", label: "No background") { onPick("") }
            ForEach(Palette.textBackgroundSwatches, id: \.hex) { swatch in
                chip(fill: Palette.color(named: swatch.hex), selected: swatch.hex == current,
                     id: swatch.hex, label: swatch.name) { onPick(swatch.hex) }
            }
            Button(action: onCustom) {
                ZStack {
                    if isCustom {
                        RoundedRectangle(cornerRadius: 12).fill(Palette.color(named: current))
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xE5D9CE))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AngularGradient(colors: Tokens.conic, center: .center, angle: .degrees(90)))
                    }
                    Text("+")
                        .font(Sans.font(size: 34, weight: 500))
                        .foregroundStyle(.white)
                        .offset(y: 3)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .overlay(SelectionRing(on: isCustom))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom background")
            .accessibilityAddTraits(isCustom ? .isSelected : [])
            .accessibilityIdentifier("style.highlight.custom")
        }
        .padding(.horizontal, 5)
        .frame(height: 34)
    }

    private func chip(
        fill: Color?, selected: Bool, id: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text("Aa")
                .font(Sans.font(size: 14, weight: 500))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    if let fill {
                        RoundedRectangle(cornerRadius: 12).fill(fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                    }
                }
                .overlay(SelectionRing(on: selected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(copy: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("style.highlight.\(id)")
    }
}

/// The picked background chip: a 1.5 pt linen ring inside its edge (not
/// drawn in the handoff; the row needs one).
private struct SelectionRing: View {
    let on: Bool

    var body: some View {
        if on {
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 2)
                .strokeBorder(Tokens.linen, lineWidth: 1.5)
        }
    }
}
