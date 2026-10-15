import MiraNoteKit
import SwiftUI

// The text editor's accessory (handoff screens 11-20), bottom to top above
// the keyboard: the "Mira Dictation" strip, the persistent five-icon tool
// bar, and the active tool's secondary row. Pure views: CanvasScene owns
// the state and passes it in.

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

/// "MiraNote text icon toolbar": 30 tall, r15 frosted glass. Exactly one
/// tool is active and drawn inverted (light).
struct TextToolBar: View {
    let active: TextTool
    let alignment: TextAlign
    let onSelect: (TextTool) -> Void

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
                .accessibilityValue(tool == .align ? alignment.rawValue : "")
                .accessibilityAddTraits(tool == active ? .isSelected : [])
                .accessibilityIdentifier(identifier(tool))
                .position(x: geo.size.width * (Self.centers[tool] ?? 0), y: geo.size.height / 2)
            }
        }
        .frame(height: 30)
        .background(
            // The page under it is already blurred by the scrim, so the
            // glass is the drawn 23% warm white alone.
            Capsule()
                .fill(Tokens.warmWhite.opacity(0.23))
                .overlay(Capsule().strokeBorder(Tokens.barRim, lineWidth: 0.661))
                .shadow(color: Palette.ink.opacity(0.08), radius: 3, y: 5.3)
        )
    }

    @ViewBuilder private func glyph(_ tool: TextTool, active: Bool) -> some View {
        let ink = active ? Tokens.warmWhite : Tokens.forest
        switch tool {
        case .font:
            Text("Aa")
                .font(Sans.font(size: 14.446, weight: 700))
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
        case .font: return "Font and size"
        case .color: return "Text color"
        case .ai: return "Rewrite"
        case .align: return "Alignment"
        case .background: return "Text background"
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

// MARK: - Dictation strip

/// "Mira dictation strip": press and hold to talk. The subtitle reads
/// "Listening..." while the mic is live and carries the last hint (why
/// nothing landed, a failed rewrite) otherwise.
struct DictationStrip: View {
    let listening: Bool
    let hint: String?

    var body: some View {
        HStack(spacing: 0) {
            Image("text.dictation.mic")
                .renderingMode(.template)
                .resizable()
                .frame(width: 12, height: 12)
                .foregroundStyle(Color(hex: 0xF7F4E9))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Tokens.forest))
                .scaleEffect(listening ? 1.15 : 1)
                .animation(listening ? .easeInOut(duration: 0.6).repeatForever() : .default, value: listening)
                .padding(.trailing, 8)
            Text("Mira Dictation")
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Palette.ink)
                .frame(width: 104, alignment: .leading)
                .padding(.trailing, 2)
            Text(listening ? "Listening..." : (hint ?? "accurate voice-to-text"))
                .font(Sans.font(size: 10, weight: 400))
                .foregroundStyle(listening ? Tokens.forest : Color(hex: 0x8F7E76))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("Hold")
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Tokens.forest)
                .frame(width: 34)
                .padding(.trailing, 13)
        }
        .padding(.leading, 9)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.54))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
                .shadow(color: Palette.ink.opacity(0.10), radius: 6, y: 12)
        )
    }
}

// MARK: - Font row

/// "MiraNote font carousel": 65x35 chips, each name in its own face, the
/// selected one forest. S/M/L follow as trailing chips (not drawn; kept).
struct FontChipRow: View {
    let fontName: String
    let pointSize: CGFloat
    let onFont: (String) -> Void
    let onSize: (TextSizeChoice) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TextFace.choices, id: \.name) { face in
                        let selected = face.name == fontName
                        Button { onFont(face.name) } label: {
                            Text(face.label)
                                .font(Font(TextFace.uiFont(name: face.name, size: 14.5, weight: 500)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 59)
                                .foregroundStyle(selected ? .white : Tokens.forest)
                                .frame(width: 65, height: 35)
                                .background(FontChipBackground(selected: selected))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("style.font.\(face.label)")
                        .id(face.name)
                    }
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 3)
                    ForEach(TextSizeChoice.allCases, id: \.self) { choice in
                        let selected = abs(choice.pointSize - pointSize) < 0.5
                        Button { onSize(choice) } label: {
                            Text(choice.label)
                                .font(Sans.font(size: 14.5, weight: 700))
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
                .padding(.horizontal, 17)
                .padding(.vertical, 8)
            }
            .padding(.vertical, -8)
            .onAppear { proxy.scrollTo(fontName, anchor: .center) }
        }
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
                .accessibilityLabel(swatch.name)
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
    let selected: TextRewriteSession.Choice
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
                                .font(Sans.font(size: 10, weight: 500))
                                .foregroundStyle(on ? Tokens.linen : Tokens.deepForest)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .background(
                        Capsule()
                            .fill(on ? Tokens.deepForest : Color(hex: 0xDCCFC0))
                            .overlay(Capsule().strokeBorder(on ? Tokens.deepForest : Tokens.rosewood, lineWidth: 1))
                    )
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .padding(.vertical, -11)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("style.ai.\(choice.rawValue)")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Tokens.warmWhite.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tokens.barRim, lineWidth: 0.66))
        )
        .opacity(enabled ? 1 : 0.6)
    }

    private func title(_ choice: TextRewriteSession.Choice) -> String {
        switch choice {
        case .original: return "Original"
        case .clean: return "Clean up"
        case .expand: return "Expand"
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
                        .font(Sans.font(size: 32, weight: 500))
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
                .font(Sans.font(size: 12, weight: 500))
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
        .accessibilityLabel(label)
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
