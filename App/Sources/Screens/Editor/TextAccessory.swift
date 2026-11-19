import MiraNoteKit
import SwiftUI

// The text editor's accessory (handoff screens 11-20, #205), bottom to top
// above the keyboard: the Mira chat box with its mic, and one row in the
// text slot -- Back and the six-icon text row, or one tool's row in its
// place with its own Back. Pure views: CanvasScene owns the state and
// passes it in.

/// The six text tools, in the text row's order (K1B).
enum TextTool: CaseIterable {
    case font, size, color, ai, align, background
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

/// "MiraNote text icon toolbar": 36 tall, a frosted glass capsule. A tap on
/// a tool opens its row in the bar's place; Align steps the alignment.
struct TextToolBar: View {
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

    /// The first and last tool centers in the drawn 342 pt bar; the six
    /// tools are spread evenly between them.
    private static let firstCenter: CGFloat = 23.5 / 342
    private static let lastCenter: CGFloat = 309.9 / 342

    var body: some View {
        GeometryReader { geo in
            let tools = TextTool.allCases
            ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                let center = Self.firstCenter
                    + (Self.lastCenter - Self.firstCenter) * CGFloat(index) / CGFloat(tools.count - 1)
                Button {
                    onSelect(tool)
                } label: {
                    glyph(tool)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(tool))
                .accessibilityValue(tool == .align ? Self.spoken(alignment) : "")
                .accessibilityIdentifier(identifier(tool))
                .position(x: geo.size.width * center, y: geo.size.height / 2)
            }
        }
        .frame(height: 36)
        // The page under it is sharp now (#205): the glass blurs it itself.
        .background(TextGlass(shape: Capsule()))
    }

    @ViewBuilder private func glyph(_ tool: TextTool) -> some View {
        switch tool {
        case .font:
            Text("Aa")
                .font(Sans.font(size: 16, weight: 700))
                .foregroundStyle(.white)
                .frame(width: 29, height: 17)
                .background(Capsule().fill(Tokens.forest))
        case .size:
            // A small A and a large A (decide9 K1B).
            Image(systemName: "textformat.size")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.forest)
        case .color:
            Image("text.tool.palette")
                .resizable()
                .frame(width: 23.8, height: 23.8)
        case .ai:
            Image("text.tool.ai")
                .renderingMode(.template)
                .resizable()
                .frame(width: 27, height: 27)
                .foregroundStyle(Tokens.forest)
        case .align:
            AlignGlyph(alignment: alignment, color: Tokens.forest)
        case .background:
            Image("text.tool.background")
                .renderingMode(.template)
                .resizable()
                .frame(width: 23.8, height: 23.8)
                .foregroundStyle(Tokens.forest)
        }
    }

    private func label(_ tool: TextTool) -> String {
        switch tool {
        case .font: return String(appCopy: "Font")
        case .size: return String(appCopy: "Text size")
        case .color: return String(appCopy: "Text color")
        case .ai: return String(appCopy: "Rewrite")
        case .align: return String(appCopy: "Alignment")
        case .background: return String(appCopy: "Text background")
        }
    }

    /// The identifiers the accessory's controls had before the redesign;
    /// Aa and Size are new (K1B).
    private func identifier(_ tool: TextTool) -> String {
        switch tool {
        case .font: return "style.font"
        case .size: return "style.size"
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

/// The leading Back key of each row in the text slot. On the text row it
/// ends the writing (R1A), as a tap on the page or Esc on a hardware
/// keyboard (`WritingEscape`) does; on a tool's row it goes back to the
/// text row. A glass circle as tall as the bar beside it.
struct TextBackKey: View {
    /// `keyboard.done` ends the writing; `text.row.back` goes up a level.
    var identifier = "keyboard.done"
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
        .accessibilityIdentifier(identifier)
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

/// "MiraNote font carousel" as a snap row (P6A, R6B): 65x35 chips, each
/// name in its own face, the block's face forest. Fonts only (K1B).
struct FontChipRow: View {
    let fontName: String
    let onFont: (String) -> Void

    var body: some View {
        SnapRow(
            ids: TextFace.choices.map(\.name), selected: fontName, cellWidth: 65, spacing: 6,
            identifier: { name in "style.font.\(TextFace.choices.first { $0.name == name }?.label ?? name)" },
            onApply: onFont,
            cell: { name in
                let selected = name == fontName
                // Face names have no entry and show as given; "Classic" is copy.
                Text(copy: TextFace.choices.first { $0.name == name }?.label ?? name)
                    .font(Font(TextFace.uiFont(name: name, size: TextScale.scaled(14.5), weight: 500)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 59)
                    .foregroundStyle(selected ? .white : Tokens.forest)
                    .frame(width: 65, height: 35)
                    .background(FontChipBackground(selected: selected))
            }
        )
    }
}

// MARK: - Size row

/// S / M / L (K2A): 15 / 21 / 30, a tap applies. The block's size forest.
struct TextSizeRow: View {
    let pointSize: CGFloat
    let onSize: (TextSizeChoice) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TextSizeChoice.allCases, id: \.self) { choice in
                let selected = abs(choice.pointSize - pointSize) < 0.5
                // The block's size again would be an undo step that changes nothing.
                Button { if !selected { onSize(choice) } } label: {
                    Text(choice.label)
                        .font(Sans.font(size: 16, weight: 700))
                        .foregroundStyle(selected ? .white : Tokens.forest)
                        .frame(width: 44, height: 35)
                        .background(FontChipBackground(selected: selected))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Size \(choice.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("style.size.\(choice.label)")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 35)
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

/// The text color snap row (P7A, G18): today's swatches as 30 pt dots in
/// 44 pt cells, the block's ringed with a check, then the custom disc. A
/// custom color already on the block fills the disc.
struct ColorSwatchRow: View {
    /// The block's color as stored.
    let current: String
    /// True when `current` came from the custom sheet.
    let isCustom: Bool
    let onSwatch: (String) -> Void
    let onCustom: () -> Void

    private static let custom = "custom"

    var body: some View {
        SnapRow(
            ids: Palette.textSwatches.map(\.hex) + [Self.custom],
            selected: isCustom ? Self.custom : current, cellWidth: 44, spacing: 2,
            identifier: { "style.color.\($0)" },
            onApply: onSwatch,
            isAction: { $0 == Self.custom },
            onAction: { _ in onCustom() },
            cell: { hex in
                if hex == Self.custom {
                    CustomDisc(color: isCustom ? Palette.color(named: current) : nil, selected: isCustom,
                               darkMark: !RowColor.isDark(current))
                        .accessibilityLabel("Custom color")
                } else {
                    SwatchDisc(color: Palette.color(named: hex), selected: hex == current,
                               darkMark: !RowColor.isDark(hex))
                        .accessibilityLabel(Text(copy: Palette.textSwatches.first { $0.hex == hex }?.name ?? hex))
                }
            }
        )
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

/// The highlight snap row (P7A, G19): "none" as a slashed dot, today's
/// fills, then the custom disc.
struct TextBackgroundRow: View {
    /// The block's background as stored ("" for none).
    let current: String
    let isCustom: Bool
    let onPick: (String) -> Void
    let onCustom: () -> Void

    private static let custom = "custom"

    var body: some View {
        SnapRow(
            ids: [""] + Palette.textBackgroundSwatches.map(\.hex) + [Self.custom],
            selected: isCustom ? Self.custom : current, cellWidth: 44, spacing: 2,
            identifier: { "style.highlight.\($0.isEmpty ? "none" : $0)" },
            onApply: onPick,
            isAction: { $0 == Self.custom },
            onAction: { _ in onCustom() },
            cell: { hex in
                if hex.isEmpty {
                    NoneDisc(selected: current.isEmpty)
                        .accessibilityLabel(Text(copy: "No background"))
                } else if hex == Self.custom {
                    CustomDisc(color: isCustom ? Palette.color(named: current) : nil, selected: isCustom,
                               darkMark: !RowColor.isDark(current))
                        .accessibilityLabel("Custom background")
                } else {
                    SwatchDisc(color: Palette.color(named: hex), selected: hex == current,
                               darkMark: !RowColor.isDark(hex))
                        .accessibilityLabel(
                            Text(copy: Palette.textBackgroundSwatches.first { $0.hex == hex }?.name ?? hex)
                        )
                }
            }
        )
    }
}

/// The custom cell: the conic disc with a "+", or the custom color already
/// on the block, ringed.
private struct CustomDisc: View {
    let color: Color?
    let selected: Bool
    let darkMark: Bool

    var body: some View {
        if let color {
            SwatchDisc(color: color, selected: selected, darkMark: darkMark)
        } else {
            Circle()
                .fill(AngularGradient(colors: Tokens.conic, center: .center, angle: .degrees(90)))
                .frame(width: 30, height: 30)
                .overlay(PlusMark(size: 12, thickness: 3))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

/// No highlight: a warm white dot struck through, ringed when it is the
/// block's.
private struct NoneDisc: View {
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Tokens.warmWhite)
            .overlay(
                Rectangle()
                    .fill(Tokens.rosewood)
                    .frame(width: 1.5)
                    .rotationEffect(.degrees(45))
            )
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Tokens.rosewood.opacity(0.7), lineWidth: 1))
            .overlay {
                if selected { Circle().strokeBorder(Tokens.deepForest.opacity(0.9), lineWidth: 1.5) }
            }
            .frame(width: 30, height: 30)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
