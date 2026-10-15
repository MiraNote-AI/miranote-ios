import SwiftUI

/// Warm earthen palette. UI values follow DESIGN_TOKENS.md of the 2026-10-07
/// design handoff; `taupe`, `tan` and `sage` are older Flow 7 values kept
/// because canvas text blocks persist them by name.
enum Palette {
    static let ink = Color(hex: 0x201E1C)
    static let onInk = Color(hex: 0xF6F4E8)
    static let forest = Color(hex: 0x293322)
    /// Fill of the active tool in the bottom tool bar.
    static let selectedTool = Color(hex: 0x24382D)
    /// Fill of an inactive tool in the bottom tool bar.
    static let toolSurface = Color(hex: 0xF7F5ED)
    /// Glyph color of an inactive tool (the handoff's tool-bar SVG stroke).
    static let toolIcon = Color(hex: 0x58665B)
    static let warmWhite = Color(hex: 0xFFFDF8)
    static let taupe = Color(hex: 0x8C8073)
    static let tan = Color(hex: 0xC9B295)
    static let sage = Color(hex: 0x8E8D77)
    static let paper = Color(hex: 0xF6F4E8)
    /// Default page backdrop (mockup, 2026-07-11): dawn peach into dusk plum.
    static let backdropDawn = Color(hex: 0xF0B78E)
    static let backdropDusk = Color(hex: 0x702E4E)
    static let cardFill = Color(hex: 0xECE7D8)
    static let hairline = Color(hex: 0xD8D5CA)
    /// The design's muted #878476, darkened along the same hue until it
    /// reads at 4.5:1 or better on every surface it sits on, the panel
    /// sheet included (4.6:1 there, 6.1:1 on paper). The original is
    /// 3.4:1 on paper.
    static let textSecondary = Color(hex: 0x5E5C52)
    /// The handoff's muted #878476 as drawn: the leading nav label on editor
    /// scenes and the composer placeholder (design fidelity pass, 2026-10-15).
    static let muted = Color(hex: 0x878476)
    /// "Story canvas dim glass scrim" (screens 11-20): forest at 34% over
    /// the page and everything around the text being written.
    static let editingScrim = Color(hex: 0x293322).opacity(0.34)

    /// Resolves the palette names persisted on canvas text blocks
    /// (`TextBlock.colorName`). Unknown names fall back to ink.
    ///
    /// Saved words keep the colors they were written in: the four names
    /// whose UI token the redesign moved resolve to their pre-redesign
    /// values here, so a restyle of the app's chrome never repaints a page
    /// (or makes it differ from its earlier exports).
    static func color(named name: String) -> Color {
        switch name {
        case "ink": return Color(hex: 0x201C16)
        case "onInk": return Color(hex: 0xF6F2EA)
        case "forest": return Color(hex: 0x353F2D)
        case "textSecondary": return Color(hex: 0x8B857A)
        case "taupe": return taupe
        case "tan": return tan
        case "sage": return sage
        default:
            // A custom color picked in the editor is stored as "#RRGGBB".
            if name.count == 7, name.hasPrefix("#"), let hex = UInt32(name.dropFirst(), radix: 16) {
                return Color(hex: hex)
            }
            return color(named: "ink")
        }
    }

    /// The text-color row (handoff screens 12-13), in the drawn order;
    /// the custom disc follows them. `hex` is what TextBlock stores;
    /// `name` is what VoiceOver reads. Older blocks keep the colors they
    /// stored -- a hex never repaints.
    static let textSwatches: [(hex: String, name: String)] = [
        ("#24382D", "Forest"), ("#F1EBDD", "Linen"), ("#9B7A70", "Rosewood"),
        ("#74806B", "Sage"), ("#B4826D", "Clay"), ("#8B5662", "Plum"),
        ("#FFFFFF", "White"),
    ]

    /// The text-background row (handoff screen 18): no background (the
    /// first chip, drawn #293322 and read here as "none", outlined), Ink
    /// and Highlight; the custom chip follows them.
    static let textBackgroundSwatches: [(hex: String, name: String)] = [
        ("#171914", "Ink"), ("#B4826D", "Highlight"),
    ]
}

extension Color {
    /// Build an opaque sRGB color from a 0xRRGGBB literal.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
