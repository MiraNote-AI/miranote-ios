import Foundation

/// An sRGB color with components in 0...1, and the "#RRGGBB" form canvas
/// text and pages persist.
public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "#RRGGBB" or "RRGGBB", any case; nil for anything else.
    public init?(hex text: String) {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    public var hex: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        RGBColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    func distance(to other: RGBColor) -> Double {
        let dr = red - other.red, dg = green - other.green, db = blue - other.blue
        return dr * dr + dg * dg + db * db
    }
}

/// The custom color sheet's picker (handoff screens 14 and 20). The
/// spectrum is the design's curated field, not an HSV square: a horizontal
/// run of warm journal tones, lifted by a white veil at the top and sunk
/// toward forest at the bottom. The hue rail turns that field around the
/// color wheel, so every hue is reachable while the rail's resting point
/// shows the field exactly as drawn.
///
/// Positions are unit fractions: `x`, `y` across the spectrum, `rail` along
/// the hue rail. The view renders the spectrum from `color(x:y:rail:)`, so
/// what is drawn is what is picked.
public enum ColorField {
    /// The spectrum's horizontal stops (CSS 90deg linear-gradient).
    public static let spectrumStops: [(position: Double, color: RGBColor)] = [
        (0, RGBColor(hex: 0xFFF8E7)), (0.18, RGBColor(hex: 0xF4D6B6)), (0.38, RGBColor(hex: 0xE5AC95)),
        (0.57, RGBColor(hex: 0xCC88A4)), (0.76, RGBColor(hex: 0x847FA8)), (1, RGBColor(hex: 0x719B8E)),
    ]

    /// The hue rail's stops, as drawn.
    public static let railStops: [(position: Double, color: RGBColor)] = [
        (0, RGBColor(hex: 0xEC817D)), (0.2, RGBColor(hex: 0xF5C77B)), (0.4, RGBColor(hex: 0x8DBA8A)),
        (0.6, RGBColor(hex: 0x79B5BC)), (0.8, RGBColor(hex: 0x9A92C8)), (1, RGBColor(hex: 0xEC817D)),
    ]

    /// Where the rail shows the spectrum unturned: the handle's place in
    /// the handoff's screen 14.
    public static let restingRail: Double = 0.38

    private static let veilTop = (color: RGBColor(red: 1, green: 1, blue: 1), alpha: 0.14)
    private static let veilBottom = (color: RGBColor(hex: 0x24382D), alpha: 0.58)

    /// The spectrum as drawn (the rail at rest).
    public static func spectrum(x: Double, y: Double) -> RGBColor {
        let base = sample(spectrumStops, at: x)
        let fraction = clamp(y)
        // The CSS veil interpolates premultiplied: color*alpha and alpha.
        let alpha = veilTop.alpha + (veilBottom.alpha - veilTop.alpha) * fraction
        let premultiplied = veilTop.color.scaled(veilTop.alpha)
            .mixed(with: veilBottom.color.scaled(veilBottom.alpha), amount: fraction)
        return RGBColor(
            red: base.red * (1 - alpha) + premultiplied.red,
            green: base.green * (1 - alpha) + premultiplied.green,
            blue: base.blue * (1 - alpha) + premultiplied.blue
        )
    }

    /// The color under the spectrum target with the rail at `rail`.
    public static func color(x: Double, y: Double, rail: Double) -> RGBColor {
        spectrum(x: x, y: y).hueRotated(by: rotation(rail: rail))
    }

    /// The rail's own color under the handle.
    public static func railColor(at rail: Double) -> RGBColor {
        sample(railStops, at: rail)
    }

    /// The picker position closest to `target`, for a typed HEX, a sampled
    /// pixel or the color the sheet opens with. The current color stays
    /// `target` itself; only the target and handle move.
    public static func nearest(to target: RGBColor) -> (x: Double, y: Double, rail: Double) {
        let goal = HSL(target)
        var best = (x: 0.0, y: 0.0, rail: restingRail, distance: Double.infinity)
        let columns = 60, rows = 20
        for column in 0...columns {
            for row in 0...rows {
                let x = Double(column) / Double(columns), y = Double(row) / Double(rows)
                var sample = HSL(spectrum(x: x, y: y))
                // A grey target has no hue to turn to: keep the rail at rest.
                let turn = goal.saturation < 0.02 ? 0 : goal.hue - sample.hue
                sample.hue += turn
                let distance = sample.rgb.distance(to: target)
                if distance < best.distance {
                    best = (x, y, wrap(restingRail + turn / 360), distance)
                }
            }
        }
        return (best.x, best.y, best.rail)
    }

    /// Degrees the field turns for a rail position (one lap per rail).
    static func rotation(rail: Double) -> Double {
        (clamp(rail) - restingRail) * 360
    }

    static func sample(_ stops: [(position: Double, color: RGBColor)], at position: Double) -> RGBColor {
        let at = clamp(position)
        guard let upper = stops.firstIndex(where: { $0.position >= at }), upper > 0 else {
            return stops[0].color
        }
        let lower = stops[upper - 1], next = stops[upper]
        let span = next.position - lower.position
        return lower.color.mixed(with: next.color, amount: span > 0 ? (at - lower.position) / span : 0)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func wrap(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }
}

private extension RGBColor {
    func scaled(_ factor: Double) -> RGBColor {
        RGBColor(red: red * factor, green: green * factor, blue: blue * factor)
    }

    func hueRotated(by degrees: Double) -> RGBColor {
        guard degrees != 0 else { return self }
        var hsl = HSL(self)
        hsl.hue += degrees
        return hsl.rgb
    }
}

/// Hue in degrees, saturation and lightness in 0...1.
private struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(_ color: RGBColor) {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 0 else {
            hue = 0
            saturation = 0
            return
        }
        saturation = chroma / (1 - abs(2 * lightness - 1))
        switch high {
        case color.red: hue = 60 * ((color.green - color.blue) / chroma).truncatingRemainder(dividingBy: 6)
        case color.green: hue = 60 * ((color.blue - color.red) / chroma + 2)
        default: hue = 60 * ((color.red - color.green) / chroma + 4)
        }
    }

    var rgb: RGBColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        var turned = hue.truncatingRemainder(dividingBy: 360)
        if turned < 0 { turned += 360 }
        let sector = turned / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch sector {
        case ..<1: (red, green, blue) = (chroma, second, 0)
        case ..<2: (red, green, blue) = (second, chroma, 0)
        case ..<3: (red, green, blue) = (0, chroma, second)
        case ..<4: (red, green, blue) = (0, second, chroma)
        case ..<5: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        let offset = lightness - chroma / 2
        return RGBColor(red: red + offset, green: green + offset, blue: blue + offset)
    }
}
