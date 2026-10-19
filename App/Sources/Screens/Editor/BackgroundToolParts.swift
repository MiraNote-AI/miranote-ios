import MiraNoteKit
import SwiftUI

/// Colors the Background tool draws (handoff screen 05).
enum BackgroundToolColors {
    static let tileSelected = Color(hex: 0xFFFEFA)
    static let tileSelectedRim = Color(hex: 0x94784D)
    static let tile = Color(hex: 0xFBF8EE)
    static let rule = Color(hex: 0xD1C9B8)
    static let labelSurface = Color(hex: 0xFAF8EF)
}

// MARK: - Page type tile

/// A 67x63 page-type tile with its drawn paper sample (30 pt, at 18,10)
/// and the label inside the tile, centered on y 53.
struct PageTypeTile: View {
    let kind: PaperKind
    let selected: Bool

    private static let shape = RoundedRectangle(cornerRadius: 12)
    private let rule = BackgroundToolColors.rule

    var body: some View {
        ZStack(alignment: .topLeading) {
            Self.shape.fill(selected ? BackgroundToolColors.tileSelected : BackgroundToolColors.tile)
            sample
                .offset(x: 18, y: 10)
            Text(kind.rawValue.capitalized)
                .font(Sans.font(size: 12, weight: 500))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 15)
                .offset(y: 53 - 7.5)
        }
        .overlay(
            Self.shape.strokeBorder(
                selected ? BackgroundToolColors.tileSelectedRim : rule,
                lineWidth: selected ? 1.5 : 1
            )
        )
        .frame(height: 63)
    }

    private var sample: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(rule, lineWidth: 1))
                .frame(width: 30, height: 30)
            glyph
        }
        .frame(width: 30, height: 30, alignment: .topLeading)
    }

    /// Lines and dots placed as the handoff draws them, relative to the
    /// sample's top-left corner.
    @ViewBuilder private var glyph: some View {
        switch kind {
        case .blank:
            EmptyView()
        case .grid:
            ForEach([5.0, 11, 17], id: \.self) { top in
                line(left: 4, top: top, width: 20, height: 1)
            }
            ForEach([7.0, 13, 19], id: \.self) { left in
                line(left: left, top: 3, width: 1, height: 22)
            }
        case .lined:
            ForEach([5.0, 10, 15, 20], id: \.self) { top in
                line(left: 4, top: top, width: 20, height: 1)
            }
        case .dot:
            ForEach([7.1, 14.1, 21.1], id: \.self) { centerX in
                ForEach([8.1, 15.1, 22.1], id: \.self) { centerY in
                    Circle().fill(rule)
                        .frame(width: 2.2, height: 2.2)
                        .offset(x: centerX - 1.1, y: centerY - 1.1)
                }
            }
        }
    }

    private func line(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Rectangle().fill(rule)
            .frame(width: width, height: height)
            .offset(x: left, y: top)
    }
}

// MARK: - Color swatch

/// A 28 pt page-color dot: a white 1 pt rim at rest, a 1.5 pt black ring
/// when it is the page's color.
struct PageSwatch: View {
    let color: Color
    let selected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(selected ? Color.black : Color.white, lineWidth: selected ? 1.5 : 1))
            .frame(width: 28, height: 28)
    }
}

/// The handoff's Custom dot: a dawn-to-sage sweep with a forest "+".
struct CustomColorDot: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xFFF8E7), location: 0),
                    .init(color: Color(hex: 0xF4D6B6), location: 0.18),
                    .init(color: Color(hex: 0xE5AC95), location: 0.38),
                    .init(color: Color(hex: 0xCC88A4), location: 0.57),
                    .init(color: Color(hex: 0x847FA8), location: 0.76),
                    .init(color: Color(hex: 0x719B8E), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .overlay(
                Text("+")
                    .font(Sans.font(size: 22, weight: 700))
                    .foregroundStyle(Palette.selectedTool)
                    .offset(y: 2)
            )
            .frame(width: 28, height: 28)
    }
}

/// The handoff's Pick dot: forest with the eyedropper glyph.
struct PickColorDot: View {
    var body: some View {
        Circle()
            .fill(Palette.selectedTool)
            .overlay(
                Image("background.eyedropper")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 20, height: 20)
            )
            .frame(width: 28, height: 28)
    }
}

// MARK: - Curated set card

/// How a curated set's 126x102 card looks: its photo, the palette band
/// over the label surface, and the two face names in their own faces.
struct CuratedSetLook {
    let displayLabel: String
    let bodyLabel: String
    let labelColor: Color
    let band: Band
    var labelSurface = BackgroundToolColors.labelSurface
    /// Light lettering on the dark Optima card carries a soft shadow.
    var labelShadow = false

    enum Band {
        /// A CSS linear gradient: angle in degrees (0 points up), stops in
        /// gradient-line fractions (values past 0...1 are allowed), drawn in
        /// a box `frame` relative to the label surface's top-left.
        case gradient(angle: Double, stops: [(UInt32, Double)], frame: CGRect)
        /// A photo strip from the asset catalog.
        case image(String)
    }

    /// The handoff's eight cards (screen 05), keyed by `CuratedSet.id`.
    /// Bands 01 and 02 are sampled from `screen.png`: their Figma stops are
    /// out of order and render unlike the raw CSS.
    static func look(for set: CuratedSet) -> CuratedSetLook {
        switch set.id {
        case "poppins-lora":
            return CuratedSetLook(
                displayLabel: "Poppins", bodyLabel: "Lora", labelColor: .black,
                band: .gradient(angle: 0, stops: [(0xFE6404, 0), (0xA21101, 1)],
                                frame: CGRect(x: 0, y: 0, width: 126, height: 40)))
        case "didot-cardo":
            return CuratedSetLook(
                displayLabel: "Didot", bodyLabel: "Cardo", labelColor: Color(hex: 0x2D372C),
                band: .gradient(angle: 180, stops: [(0xFCE7A6, 0), (0xFCD766, 0.42), (0xEC9E36, 1)],
                                frame: CGRect(x: 0, y: 0, width: 126, height: 40)))
        case "merriweather-raleway":
            return CuratedSetLook(
                displayLabel: "Merriweather", bodyLabel: "Raleway", labelColor: .black,
                band: .image("curated.merriweather-raleway.band"))
        case "montserrat-opensans":
            return CuratedSetLook(
                displayLabel: "Montserrat", bodyLabel: "Open Sans", labelColor: Color(hex: 0x741000),
                band: .gradient(angle: 0, stops: [
                    (0x35364B, 0.20207), (0x7B502E, 0.40934), (0x7D96CA, 0.70978), (0xFBFBFC, 0.99163)
                ], frame: CGRect(x: 0, y: 0, width: 126, height: 62)))
        case "playfair-oswald":
            return CuratedSetLook(
                displayLabel: "Playfair Display", bodyLabel: "Oswald", labelColor: Color(hex: 0xFEF8DD),
                band: .gradient(angle: 180, stops: [
                    (0x7CAAB3, 0.3125), (0x3E8AB7, 0.625), (0x236FB3, 0.8125), (0x66A6DB, 0.99519)
                ], frame: CGRect(x: 0, y: 0, width: 126, height: 45)))
        case "bodoni-raleway":
            return CuratedSetLook(
                displayLabel: "Bodoni", bodyLabel: "Raleway", labelColor: Color(hex: 0xD8FFF5),
                band: .gradient(angle: 186.45, stops: [(0x18231B, 0.10211), (0x415A58, 0.50947), (0x81A7A3, 0.89105)],
                                frame: CGRect(x: 0, y: 0, width: 126, height: 40)))
        case "optima-darkergrotesque":
            return CuratedSetLook(
                displayLabel: "Optima", bodyLabel: "Darker Grotesque", labelColor: .white,
                band: .gradient(angle: 180, stops: [(0x1D2223, 0), (0x152A15, 0.25), (0x8B2D15, 0.5), (0xFFBD77, 1)],
                                frame: CGRect(x: 0, y: 0, width: 126, height: 40)),
                labelSurface: Palette.selectedTool, labelShadow: true)
        default:
            // "montserrat-opensans-rose": the Figma's first stop renders
            // behind the others, as on cards 01 and 02.
            return CuratedSetLook(
                displayLabel: "Montserrat", bodyLabel: "Open Sans", labelColor: Color(hex: 0x5C2626),
                band: .gradient(angle: -4.04, stops: [(0xF59081, 0.37051), (0xBBB3A9, 1.0755)],
                                frame: CGRect(x: 0, y: 0, width: 126, height: 40)))
        }
    }
}

struct CuratedSetCard: View {
    let set: CuratedSet
    let worn: Bool

    private static let shape = RoundedRectangle(cornerRadius: 10)

    var body: some View {
        let look = CuratedSetLook.look(for: set)
        VStack(spacing: 0) {
            Image("curated.\(set.id)")
                .resizable()
                .scaledToFill()
                .frame(width: 126, height: 62)
                .clipped()
            ZStack(alignment: .top) {
                look.labelSurface
                band(look.band)
                VStack(spacing: 0) {
                    Text(look.displayLabel)
                        .font(Font(TextFace.uiFont(name: set.displayFont, size: 12)))
                        .frame(height: 15)
                        .padding(.top, 5)
                    Text(look.bodyLabel)
                        .font(Font(TextFace.uiFont(name: set.bodyFont, size: 10)))
                        .frame(height: 13)
                        .padding(.top, 2)
                }
                .lineLimit(1)
                .foregroundStyle(look.labelColor)
                .shadow(color: .black.opacity(look.labelShadow ? 0.25 : 0), radius: 0.6, y: 0.8)
            }
            .frame(width: 126, height: 40)
            .clipped()
        }
        .frame(width: 126, height: 102)
        .background(Palette.paper)
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(worn ? Palette.ink : .clear, lineWidth: 2))
    }

    @ViewBuilder private func band(_ band: CuratedSetLook.Band) -> some View {
        switch band {
        case .image(let name):
            Image(name)
                .resizable()
                .frame(width: 126, height: 40)
        case .gradient(let angle, let stops, let frame):
            CSSLinearGradient(angle: angle, stops: stops, size: frame.size)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .frame(width: 126, height: 40, alignment: .topLeading)
        }
    }
}

/// A CSS `linear-gradient(<angle>, ...)` in a box of known size: 0 deg points
/// up, 90 right; the gradient line spans |w sin a| + |h cos a| through the
/// center, and stops past either end are cut to the box.
struct CSSLinearGradient: View {
    let angle: Double
    let stops: [(UInt32, Double)]
    let size: CGSize

    var body: some View {
        let radians = angle * .pi / 180
        let (dx, dy) = (sin(radians), -cos(radians))
        let length = abs(size.width * dx) + abs(size.height * dy)
        let half = CGPoint(x: dx * length / 2 / size.width, y: dy * length / 2 / size.height)
        Rectangle().fill(LinearGradient(
            stops: Self.clipped(stops).map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) },
            startPoint: UnitPoint(x: 0.5 - half.x, y: 0.5 - half.y),
            endPoint: UnitPoint(x: 0.5 + half.x, y: 0.5 + half.y)
        ))
    }

    /// Stops cut to 0...1, interpolating the colors at the cuts.
    static func clipped(_ stops: [(UInt32, Double)]) -> [(UInt32, Double)] {
        guard let first = stops.first, let last = stops.last else { return [] }
        func color(at location: Double) -> UInt32 {
            if location <= first.1 { return first.0 }
            if location >= last.1 { return last.0 }
            for (lower, upper) in zip(stops, stops.dropFirst()) where location <= upper.1 {
                let span = upper.1 - lower.1
                return mix(lower.0, upper.0, span > 0 ? (location - lower.1) / span : 1)
            }
            return last.0
        }
        let inside = stops.filter { $0.1 > 0 && $0.1 < 1 }
        return [(color(at: 0), 0)] + inside + [(color(at: 1), 1)]
    }

    private static func mix(_ lhs: UInt32, _ rhs: UInt32, _ fraction: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let from = Double((lhs >> shift) & 0xFF)
            let to = Double((rhs >> shift) & 0xFF)
            return UInt32((from + (to - from) * fraction).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}
