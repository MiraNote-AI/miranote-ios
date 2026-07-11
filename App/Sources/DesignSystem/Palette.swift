import SwiftUI

/// Flow 7 palette -- warm earthen. `forest` and `ink` are the accents
/// (this is the client's delivered identity, not the terracotta default).
/// Values sampled from the Figma Flow 7 frames; tuned during QA.
enum Palette {
    static let ink = Color(hex: 0x201C16)
    static let onInk = Color(hex: 0xF6F2EA)
    static let forest = Color(hex: 0x353F2D)
    static let taupe = Color(hex: 0x8C8073)
    static let tan = Color(hex: 0xC9B295)
    static let sage = Color(hex: 0x8E8D77)
    static let paper = Color(hex: 0xF4F0E7)
    /// Default page backdrop (mockup, 2026-07-11): dawn peach into dusk plum.
    static let backdropDawn = Color(hex: 0xF0B78E)
    static let backdropDusk = Color(hex: 0x702E4E)
    static let cardFill = Color(hex: 0xE7DFD1)
    static let sheetFill = Color(hex: 0xDCD5C6)
    static let hairline = Color(hex: 0xE2DBCD)
    static let textSecondary = Color(hex: 0x8B857A)

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
        default: return ink
        }
    }
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
