import SwiftUI
import UIKit

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
    static let sheetFill = Color(hex: 0xDCD5C6)
    static let hairline = Color(hex: 0xD8D5CA)
    /// The design's muted #878476, darkened along the same hue until it
    /// reads at 4.5:1 or better on paper, tool surface, card fill and white
    /// (worst case 4.67:1 on card fill). The original is 3.4:1 on paper.
    static let textSecondary = Color(hex: 0x68665B)

    /// Resolves the palette names persisted on canvas text blocks
    /// (`TextBlock.colorName`). Unknown names fall back to ink.
    static func color(named name: String) -> Color {
        switch name {
        case "onInk": return onInk
        case "forest": return forest
        case "taupe": return taupe
        case "tan": return tan
        case "sage": return sage
        case "textSecondary": return textSecondary
        default:
            // A custom color picked in the editor is stored as "#RRGGBB".
            if name.count == 7, name.hasPrefix("#"), let hex = UInt32(name.dropFirst(), radix: 16) {
                return Color(hex: hex)
            }
            return ink
        }
    }

    /// The editor's quick swatches for text and text backgrounds: the
    /// handoff's text-color row (screens 12-13), as stored "#RRGGBB" names.
    static let textSwatches = [
        "#201E1C", "#FFFDF8", "#24382D", "#8C7468", "#7B8A70", "#C98F72", "#8B5962", "#E5AC95",
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

    /// The "#RRGGBB" form TextBlock stores for a custom color (alpha dropped).
    var hexName: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
