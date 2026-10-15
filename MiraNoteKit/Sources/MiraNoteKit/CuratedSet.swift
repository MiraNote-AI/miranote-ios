import Foundation

/// One of the Background tool's curated sets (handoff screen 05): a display
/// face for titles, a body face for the rest, the text color they are set in
/// and the page backdrop they sit on. Applying one dresses the whole page in
/// one undo step (`CanvasViewModel.applyCuratedSet`).
public struct CuratedSet: Equatable, Sendable, Identifiable {
    public let id: String
    /// Font family names, as `TextBlock.fontName` stores them.
    public let displayFont: String
    public let bodyFont: String
    /// "#RRGGBB", as `TextBlock.colorName` stores a custom color.
    public let textColor: String
    /// "#RRGGBB", as `Memory.pageColorName` stores a page color.
    public let pageColor: String

    public init(id: String, displayFont: String, bodyFont: String, textColor: String, pageColor: String) {
        self.id = id
        self.displayFont = displayFont
        self.bodyFont = bodyFont
        self.textColor = textColor
        self.pageColor = pageColor
    }

    /// The handoff's eight sets, in carousel order. Text colors are the
    /// card labels'; page colors are taken from each card's palette band,
    /// where its label sits.
    public static let all: [CuratedSet] = [
        CuratedSet(id: "poppins-lora", displayFont: "Poppins", bodyFont: "Lora",
                   textColor: "#000000", pageColor: "#D03A02"),
        CuratedSet(id: "didot-cardo", displayFont: "Didot", bodyFont: "Cardo",
                   textColor: "#2D372C", pageColor: "#FCD766"),
        CuratedSet(id: "merriweather-raleway", displayFont: "Merriweather", bodyFont: "Raleway",
                   textColor: "#000000", pageColor: "#879064"),
        CuratedSet(id: "montserrat-opensans", displayFont: "Montserrat", bodyFont: "Open Sans",
                   textColor: "#741000", pageColor: "#FBFBFC"),
        CuratedSet(id: "playfair-oswald", displayFont: "Playfair Display", bodyFont: "Oswald",
                   textColor: "#FEF8DD", pageColor: "#236FB3"),
        CuratedSet(id: "bodoni-raleway", displayFont: "Bodoni 72", bodyFont: "Raleway",
                   textColor: "#D8FFF5", pageColor: "#415A58"),
        CuratedSet(id: "optima-darkergrotesque", displayFont: "Optima", bodyFont: "Darker Grotesque",
                   textColor: "#FFFFFF", pageColor: "#24382D"),
        CuratedSet(id: "montserrat-opensans-rose", displayFont: "Montserrat", bodyFont: "Open Sans",
                   textColor: "#5C2626", pageColor: "#F59081")
    ]
}

extension CanvasViewModel {
    /// Dresses the page in a curated set as ONE undo step: titles take the
    /// display face, the rest the body face, every block the set's text
    /// color, and the page the set's color (a painted backdrop gives way,
    /// as with any page color). A page without words still takes the color.
    /// A set the page already wears records nothing.
    public func applyCuratedSet(_ set: CuratedSet) {
        let styled = memory.items.map { item -> CanvasItem in
            guard case .text(var block) = item.content else { return item }
            block.fontName = block.pointSize >= Self.displayPointSize ? set.displayFont : set.bodyFont
            block.colorName = set.textColor
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

    /// The set the page is wearing: its page color, and every text block in
    /// the set's faces and color. Two sets share faces (04 and 08), so the
    /// page color is what tells them apart.
    public func wornCuratedSet(in sets: [CuratedSet] = CuratedSet.all) -> CuratedSet? {
        guard memory.backgroundFileName.isEmpty else { return nil }
        let blocks: [TextBlock] = memory.items.compactMap {
            if case .text(let block) = $0.content { return block }
            return nil
        }
        return sets.first { set in
            memory.pageColorName == set.pageColor && blocks.allSatisfy {
                $0.colorName == set.textColor
                    && $0.fontName == ($0.pointSize >= Self.displayPointSize ? set.displayFont : set.bodyFont)
            }
        }
    }
}
