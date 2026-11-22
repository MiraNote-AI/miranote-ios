import Foundation

/// One of the Background tool's curated sets (handoff screen 05): a display
/// face for titles, the text color the page is set in and the page backdrop
/// it sits on. Applying one dresses the whole page in one undo step
/// (`CanvasViewModel.applyCuratedSet`).
public struct CuratedSet: Equatable, Sendable, Identifiable {
    public let id: String
    /// A font family name, as `TextBlock.fontName` stores it.
    public let displayFont: String
    /// "#RRGGBB", as `TextBlock.colorName` stores a custom color.
    public let textColor: String
    /// "#RRGGBB", as `Memory.pageColorName` stores a page color.
    public let pageColor: String

    public init(id: String, displayFont: String, textColor: String, pageColor: String) {
        self.id = id
        self.displayFont = displayFont
        self.textColor = textColor
        self.pageColor = pageColor
    }

    /// The handoff's eight sets, in carousel order. Text and page colors
    /// are taken from the handoff's set cards (screen 05).
    public static let all: [CuratedSet] = [
        CuratedSet(id: "poppins-lora", displayFont: "Poppins", textColor: "#000000", pageColor: "#D03A02"),
        CuratedSet(id: "didot-cardo", displayFont: "Didot", textColor: "#2D372C", pageColor: "#FCD766"),
        CuratedSet(id: "merriweather-raleway", displayFont: "Merriweather", textColor: "#000000", pageColor: "#879064"),
        CuratedSet(id: "montserrat-opensans", displayFont: "Montserrat", textColor: "#741000", pageColor: "#FBFBFC"),
        CuratedSet(id: "playfair-oswald", displayFont: "Playfair Display", textColor: "#FEF8DD", pageColor: "#236FB3"),
        CuratedSet(id: "bodoni-raleway", displayFont: "Bodoni 72", textColor: "#D8FFF5", pageColor: "#415A58"),
        CuratedSet(id: "optima-darkergrotesque", displayFont: "Optima", textColor: "#FFFFFF", pageColor: "#24382D"),
        CuratedSet(id: "montserrat-opensans-rose", displayFont: "Montserrat",
                   textColor: "#5C2626", pageColor: "#F59081")
    ]
}

extension CanvasViewModel {
    /// Dresses the page in a curated set as ONE undo step: titles (text of
    /// 24 pt and up) take the display face while body text keeps its own
    /// (R4A), every block the set's text color -- except one on a text
    /// background, which keeps the color it reads in there -- and the page
    /// the set's color (a painted backdrop gives way, as with any page
    /// color). A page without words still takes the color. A set the page
    /// already wears records nothing.
    public func applyCuratedSet(_ set: CuratedSet) {
        let styled = memory.items.map { item -> CanvasItem in
            guard case .text(var block) = item.content else { return item }
            if block.pointSize >= Self.displayPointSize { block.fontName = set.displayFont }
            if block.backgroundColorName.isEmpty { block.colorName = set.textColor }
            var item = item
            item.content = .text(block)
            return item
        }
        let recolors = memory.pageColorName != set.pageColor || !memory.backgroundFileName.isEmpty
        guard styled != memory.items || recolors else { return }
        beginChange()
        memory.items = styled
        memory.pageColorName = set.pageColor
        memory.backgroundFileName = ""
        memory.backgroundSummary = ""
    }

    /// The set the page is wearing: its page color, every title in the
    /// set's display face and every block in its text color. Two sets share
    /// faces (04 and 08), so the page color is what tells them apart.
    public func wornCuratedSet(in sets: [CuratedSet] = CuratedSet.all) -> CuratedSet? {
        guard memory.backgroundFileName.isEmpty else { return nil }
        let blocks: [TextBlock] = memory.items.compactMap {
            if case .text(let block) = $0.content { return block }
            return nil
        }
        return sets.first { set in
            memory.pageColorName == set.pageColor && blocks.allSatisfy {
                ($0.colorName == set.textColor || !$0.backgroundColorName.isEmpty)
                    && ($0.pointSize < Self.displayPointSize || $0.fontName == set.displayFont)
            }
        }
    }
}
