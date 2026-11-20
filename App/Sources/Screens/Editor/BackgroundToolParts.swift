import MiraNoteKit
import SwiftUI

/// Colors the Background tool draws (handoff screen 05).
enum BackgroundToolColors {
    static let tileSelected = Color(hex: 0xFFFEFA)
    static let tile = Color(hex: 0xFBF8EE)
    static let rule = Color(hex: 0xD1C9B8)
}

extension PaperKind {
    /// The page type's name in the app's language.
    var title: String {
        switch self {
        case .blank: return String(appCopy: "Blank")
        case .grid: return String(appCopy: "Grid")
        case .lined: return String(appCopy: "Lined")
        case .dot: return String(appCopy: "Dot")
        }
    }
}

// MARK: - Tray and ring

/// The frosted tray a Background row sits in (P2A).
struct BackgroundTray: View {
    var body: some View {
        GlassSurface(shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
                     tint: Palette.warmWhite.opacity(0.55), shadowOpacity: 0.06, shadowRadius: 6, shadowY: 4)
    }
}

extension View {
    /// Today's thin dark ring around the chosen cell (P4A), a little
    /// outside its shape.
    func selectionRing<S: InsettableShape>(_ shape: S, selected: Bool) -> some View {
        overlay {
            if selected {
                shape.inset(by: -4).stroke(Palette.ink, lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Page type tile

/// A page type as an icon-only 34 pt tile (F5B): its paper drawn small,
/// ringed when it is the page's.
struct PageTypeTile: View {
    let kind: PaperKind
    let selected: Bool

    private static let shape = RoundedRectangle(cornerRadius: 10)
    private let rule = Palette.toolIcon

    var body: some View {
        sample
            .scaleEffect(2 / 3)
            .frame(width: 34, height: 34)
            .background(Self.shape.fill(selected ? BackgroundToolColors.tileSelected : BackgroundToolColors.tile))
            .overlay(Self.shape.strokeBorder(BackgroundToolColors.rule, lineWidth: 1))
            .selectionRing(Self.shape, selected: selected)
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

// MARK: - Color dots

/// A 32 pt page-color dot with a hairline rim, ringed when it is the page's
/// color.
struct PageSwatch: View {
    let color: Color
    let selected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
            .frame(width: 32, height: 32)
            .selectionRing(Circle(), selected: selected)
    }
}

/// Default: the page's own dawn-to-dusk backdrop, no color -- a warm white
/// dot struck through.
struct DefaultColorDot: View {
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Palette.warmWhite)
            .overlay(
                Rectangle()
                    .fill(Color(hex: 0xB4533A))
                    .frame(width: 1.5)
                    .rotationEffect(.degrees(45))
            )
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
            .frame(width: 32, height: 32)
            .selectionRing(Circle(), selected: selected)
    }
}

/// The page's latest painting by Mira: a soft sky with sparkles.
struct PaintedColorDot: View {
    let selected: Bool

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(hex: 0xC9D8EE), Color(hex: 0xE9DDF0), Color(hex: 0xF4DCD3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
            .frame(width: 32, height: 32)
            .selectionRing(Circle(), selected: selected)
    }
}

/// The handoff's Custom dot: a dawn-to-sage sweep with a forest "+",
/// ringed while the page wears a color of its own.
struct CustomColorDot: View {
    let selected: Bool

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
            .frame(width: 32, height: 32)
            .selectionRing(Circle(), selected: selected)
    }
}

/// Pick: the eyedropper glyph on a warm white dot.
struct PickColorDot: View {
    var body: some View {
        Circle()
            .fill(Palette.warmWhite)
            .overlay(
                Image("background.eyedropper")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(Palette.forest)
                    .frame(width: 18, height: 18)
            )
            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
            .frame(width: 32, height: 32)
    }
}

// MARK: - Curated set card

/// How a curated set's card looks: its palette band and its display
/// face's name.
struct CuratedSetLook {
    let displayLabel: String
    let band: Band

    enum Band {
        /// A CSS linear gradient: angle in degrees (0 points up), stops in
        /// gradient-line fractions (values past 0...1 are allowed).
        case gradient(angle: Double, stops: [(UInt32, Double)])
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
                displayLabel: "Poppins",
                band: .gradient(angle: 0, stops: [(0xFE6404, 0), (0xA21101, 1)]))
        case "didot-cardo":
            return CuratedSetLook(
                displayLabel: "Didot",
                band: .gradient(angle: 180, stops: [(0xFCE7A6, 0), (0xFCD766, 0.42), (0xEC9E36, 1)]))
        case "merriweather-raleway":
            return CuratedSetLook(
                displayLabel: "Merriweather",
                band: .image("curated.merriweather-raleway.band"))
        case "montserrat-opensans":
            return CuratedSetLook(
                displayLabel: "Montserrat",
                band: .gradient(angle: 0, stops: [
                    (0x35364B, 0.20207), (0x7B502E, 0.40934), (0x7D96CA, 0.70978), (0xFBFBFC, 0.99163)
                ]))
        case "playfair-oswald":
            return CuratedSetLook(
                displayLabel: "Playfair Display",
                band: .gradient(angle: 180, stops: [
                    (0x7CAAB3, 0.3125), (0x3E8AB7, 0.625), (0x236FB3, 0.8125), (0x66A6DB, 0.99519)
                ]))
        case "bodoni-raleway":
            return CuratedSetLook(
                displayLabel: "Bodoni",
                band: .gradient(angle: 186.45, stops: [(0x18231B, 0.10211), (0x415A58, 0.50947), (0x81A7A3, 0.89105)]))
        case "optima-darkergrotesque":
            return CuratedSetLook(
                displayLabel: "Optima",
                band: .gradient(angle: 180, stops: [(0x1D2223, 0), (0x152A15, 0.25), (0x8B2D15, 0.5), (0xFFBD77, 1)]))
        default:
            // "montserrat-opensans-rose": the Figma's first stop renders
            // behind the others, as on cards 01 and 02.
            return CuratedSetLook(
                displayLabel: "Montserrat",
                band: .gradient(angle: -4.04, stops: [(0xF59081, 0.37051), (0xBBB3A9, 1.0755)]))
        }
    }
}

/// A set as a 40x52 mini page (P5A): its palette band over "Aa" in its
/// display face, ringed while the page wears it.
struct CuratedSetCard: View {
    let set: CuratedSet
    let worn: Bool

    private static let shape = RoundedRectangle(cornerRadius: 9)
    private static let size = CGSize(width: 40, height: 52)

    var body: some View {
        let look = CuratedSetLook.look(for: set)
        VStack(spacing: 0) {
            band(look.band)
                .frame(width: Self.size.width, height: Self.size.height / 2)
                .clipped()
            Text(verbatim: "Aa")
                .font(Font(TextFace.uiFont(name: set.displayFont, size: 16)))
                .foregroundStyle(Palette.ink)
                .frame(width: Self.size.width, height: Self.size.height / 2)
                .background(Palette.warmWhite)
        }
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1))
        .shadow(color: Palette.ink.opacity(0.08), radius: 2, y: 1)
        .selectionRing(Self.shape, selected: worn)
    }

    /// The band filling the card's top half.
    @ViewBuilder private func band(_ band: CuratedSetLook.Band) -> some View {
        switch band {
        case .image(let name):
            Image(name)
                .resizable()
                .scaledToFill()
        case .gradient(let angle, let stops):
            CSSLinearGradient(angle: angle, stops: stops,
                              size: CGSize(width: Self.size.width, height: Self.size.height / 2))
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
