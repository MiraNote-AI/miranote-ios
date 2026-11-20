import Foundation

/// A color in 0-255 sRGB channels.
public struct StarColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func scaled(_ factor: Double) -> StarColor {
        StarColor(red * factor, green * factor, blue * factor)
    }

    func mixed(with other: StarColor, _ share: Double) -> StarColor {
        StarColor(red + (other.red - red) * share, green + (other.green - green) * share,
                  blue + (other.blue - blue) * share)
    }

    var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }
}

/// A star's dress, from its strip (`StarStrip.look`).
public struct StarLook: Equatable, Sendable {
    /// The strip blurred and washed toward paper.
    public let texture: StarPixels
    /// One flat tint per arm, from the strip's fifths in order.
    public let tints: [StarColor]
    /// The whole strip's color, for a star drawn flat.
    public let average: StarColor
}

/// Opaque RGBA8 pixels, row by row from the top.
public struct StarPixels: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4)
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public init(width: Int, height: Int, fill: StarColor) {
        let pixel = [fill.red, fill.green, fill.blue, 255].map { UInt8($0) }
        self.init(width: width, height: height,
                  rgba: Array(repeating: pixel, count: width * height).flatMap { $0 })
    }

    public func color(_ column: Int, _ row: Int) -> StarColor {
        let index = (row * width + column) * 4
        return StarColor(Double(rgba[index]), Double(rgba[index + 1]), Double(rgba[index + 2]))
    }

    public mutating func set(_ column: Int, _ row: Int, _ color: StarColor) {
        let index = (row * width + column) * 4
        for (offset, channel) in [color.red, color.green, color.blue].enumerated() {
            rgba[index + offset] = UInt8(min(255, max(0, channel.rounded())))
        }
        rgba[index + 3] = 255
    }
}

/// A star's paper strip (#206, design X): of the four rows of the page's
/// top half, each a quarter of that half tall, the one whose colors vary
/// most. The half-page folds up accordion-style onto that row, so the
/// star is the page folded up and kept, never cut: the strip winds into
/// the star, and its washed colors (`look`) dress the star.
public enum StarStrip {
    /// A band on the page: its middle, its turn in radians (y down; the
    /// fold's bands lie level), and its size in pixels.
    public struct Cut: Equatable, Sendable {
        public let centerX: Double
        public let centerY: Double
        public let angle: Double
        public let length: Double
        public let thickness: Double
    }

    /// The strip's raster: 32 thick by 192 long, 1:6.
    public static let stripThickness = 32
    public static let stripLength = 192
    /// The fold's page in page widths: 560 tall on a 360 page, folded in
    /// half at its middle; the top half is four rows (pleats) of 70.
    public static let foldPageHeight = 560.0 / 360
    public static let foldRows = 4
    /// A row's height in page widths (70 on a 360 page).
    public static var foldRow: Double { foldPageHeight / 2 / Double(foldRows) }
    /// The row a page with no color anywhere folds onto: under the top
    /// edge, where a photo's upper third usually lies.
    public static let plainRow = 1

    /// The row of the page's top half (0 at the top) whose colors vary
    /// most: the largest variance of CIELAB a* plus b* over a coarse grid.
    public static func foldRow(in page: StarPixels) -> Int {
        var best: (score: Double, row: Int)?
        for row in 0..<foldRows {
            var greenRed: [Double] = [], blueYellow: [Double] = []
            sample(foldCut(row, in: page), in: page, across: 6, along: 36) { column, line in
                let lab = Self.lab(page.color(Int(column), Int(line)))
                greenRed.append(lab.greenRed)
                blueYellow.append(lab.blueYellow)
            }
            let score = variance(greenRed) + variance(blueYellow)
            if score > best?.score ?? -1 { best = (score, row) }
        }
        // Paper and grey words only: nothing to choose by.
        guard let best, best.score > 1 else { return plainRow }
        return best.row
    }

    /// Row `row` of the top half as a band of `page`'s pixels.
    public static func foldCut(_ row: Int, in page: StarPixels) -> Cut {
        let width = Double(page.width), thickness = width * foldRow
        return Cut(centerX: width / 2, centerY: thickness * (Double(row) + 0.5), angle: 0, length: width,
                   thickness: thickness)
    }

    /// The band's pixels, `stripLength` by `stripThickness`, bilinear.
    public static func strip(_ cut: Cut, from page: StarPixels) -> StarPixels {
        var strip = StarPixels(width: stripLength, height: stripThickness, fill: StarColor(0, 0, 0))
        var index = 0
        sample(cut, in: page, across: stripThickness, along: stripLength) { column, row in
            strip.set(index % stripLength, index / stripLength, bilinear(page, column, row))
            index += 1
        }
        return strip
    }

    /// A text-only page's calm paper strip: its paper (the strip's median
    /// color), a little lighter or darker by the page's id (+/-3%), with
    /// its words as faint graphite. No ink is boosted.
    public static func calm(_ strip: StarPixels, id: UUID) -> StarPixels {
        let paper = median(strip)
        let lit = paper.scaled(1 + (unit(id) - 0.5) * 0.06)
        let graphite = StarColor(74, 72, 68)
        var calm = strip
        for row in 0..<strip.height {
            for column in 0..<strip.width {
                let ink = min(1, max(0, (paper.luma - strip.color(column, row).luma) / max(paper.luma, 1)))
                calm.set(column, row, lit.mixed(with: graphite, 0.3 * ink))
            }
        }
        return calm
    }

    /// How the strip dresses its star (fold demo v4, `makeStarTex`): the
    /// strip blurred, saturated 1.8x and washed 16% toward paper, so the
    /// star carries its page's colors without photo detail; five flat arm
    /// tints from the strip's fifths, saturated again (1.9x); and the
    /// average, saturated, for stars too small for any of that. A calm
    /// strip (`calm`) is not saturated: the star wears its page's own
    /// paper tint, not a louder one.
    public static func look(_ strip: StarPixels, calm: Bool = false) -> StarLook {
        let boost = calm ? 1 : 1.8, armBoost = calm ? 1 : 1.9
        let washed = recolor(blur(strip, radius: max(1, strip.width / 76))) { wash(saturate($0, boost)) }
        let fifth = washed.width / 5
        let tints = (0..<5).map { arm in
            saturate(average(washed, columns: arm * fifth..<(arm == 4 ? washed.width : (arm + 1) * fifth)), armBoost)
        }
        let whole = saturate(average(washed, columns: 0..<washed.width), boost)
        return StarLook(texture: washed, tints: tints, average: whole)
    }

    /// The paper a star's colors are washed toward (#F1E9DB).
    public static let paper = StarColor(241, 233, 219)

    static func wash(_ color: StarColor) -> StarColor {
        color.mixed(with: paper, 0.16)
    }

    /// CSS `saturate()`: the luminance-preserving matrix, clamped.
    static func saturate(_ color: StarColor, _ amount: Double) -> StarColor {
        // CSS's own names for the matrix.
        // swiftlint:disable:next identifier_name
        let r = color.red, g = color.green, b = color.blue, s = amount
        func clamp(_ value: Double) -> Double { min(255, max(0, value)) }
        return StarColor(
            clamp((0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * b),
            clamp((0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * b),
            clamp((0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * b)
        )
    }

    /// Two passes of a box blur `radius` pixels each way: close to a
    /// Gaussian, edges clamped.
    static func blur(_ image: StarPixels, radius: Int) -> StarPixels {
        var out = image
        for _ in 0..<2 {
            out = boxBlur(out, radius: radius, horizontal: true)
            out = boxBlur(out, radius: radius, horizontal: false)
        }
        return out
    }

    private static func boxBlur(_ image: StarPixels, radius: Int, horizontal: Bool) -> StarPixels {
        var out = image
        let span = Double(2 * radius + 1)
        for row in 0..<image.height {
            for column in 0..<image.width {
                var sum = StarColor(0, 0, 0)
                for step in -radius...radius {
                    let across = horizontal ? min(max(column + step, 0), image.width - 1) : column
                    let down = horizontal ? row : min(max(row + step, 0), image.height - 1)
                    let color = image.color(across, down)
                    sum = StarColor(sum.red + color.red, sum.green + color.green, sum.blue + color.blue)
                }
                out.set(column, row, sum.scaled(1 / span))
            }
        }
        return out
    }

    private static func recolor(_ image: StarPixels, _ change: (StarColor) -> StarColor) -> StarPixels {
        var out = image
        for row in 0..<image.height {
            for column in 0..<image.width { out.set(column, row, change(image.color(column, row))) }
        }
        return out
    }

    private static func average(_ image: StarPixels, columns: Range<Int>) -> StarColor {
        var sum = StarColor(0, 0, 0)
        for row in 0..<image.height {
            for column in columns {
                let color = image.color(column, row)
                sum = StarColor(sum.red + color.red, sum.green + color.green, sum.blue + color.blue)
            }
        }
        return sum.scaled(1 / Double(max(1, image.height * columns.count)))
    }

    /// A number in 0..<1 from the id's bytes: the same every launch.
    static func unit(_ id: UUID) -> Double {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return Double(Int(bytes[14]) << 8 | Int(bytes[15])) / 65536
    }

    // MARK: Sampling and color

    /// Visits `across` x `along` points over the band, row by row, in the
    /// page's pixel space, clamped inside it.
    private static func sample(
        _ cut: Cut, in page: StarPixels, across: Int, along: Int, _ visit: (Double, Double) -> Void
    ) {
        let cosine = cos(cut.angle), sine = sin(cut.angle)
        for row in 0..<across {
            let out = -cut.thickness / 2 + cut.thickness * Double(row) / Double(max(1, across - 1))
            for column in 0..<along {
                let forth = -cut.length / 2 + cut.length * Double(column) / Double(max(1, along - 1))
                let pageX = cut.centerX + forth * cosine - out * sine
                let pageY = cut.centerY + forth * sine + out * cosine
                visit(min(max(pageX, 0), Double(page.width) - 1.001), min(max(pageY, 0), Double(page.height) - 1.001))
            }
        }
    }

    private static func bilinear(_ image: StarPixels, _ column: Double, _ row: Double) -> StarColor {
        let column = min(max(column, 0), Double(image.width - 1)), row = min(max(row, 0), Double(image.height - 1))
        let left = Int(column), top = Int(row)
        let right = min(left + 1, image.width - 1), bottom = min(top + 1, image.height - 1)
        let across = column - Double(left), down = row - Double(top)
        let upper = image.color(left, top).mixed(with: image.color(right, top), across)
        let lower = image.color(left, bottom).mixed(with: image.color(right, bottom), across)
        return upper.mixed(with: lower, down)
    }

    private static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    private static func median(_ image: StarPixels) -> StarColor {
        let channels = (0..<3).map { channel in
            stride(from: channel, to: image.rgba.count, by: 4).map { image.rgba[$0] }.sorted()
        }
        let middle = image.width * image.height / 2
        return StarColor(Double(channels[0][middle]), Double(channels[1][middle]), Double(channels[2][middle]))
    }

    /// sRGB to CIELAB's two color axes, a* and b*, D65.
    static func lab(_ color: StarColor) -> (greenRed: Double, blueYellow: Double) {
        func linear(_ channel: Double) -> Double {
            let value = channel / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let red = linear(color.red), green = linear(color.green), blue = linear(color.blue)
        func curve(_ value: Double) -> Double {
            let knee = 6.0 / 29
            return value > knee * knee * knee ? cbrt(value) : value / (3 * knee * knee) + 4.0 / 29
        }
        let fx = curve((0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047)
        let fy = curve(0.2126729 * red + 0.7151522 * green + 0.0721750 * blue)
        let fz = curve((0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883)
        return (500 * (fx - fy), 200 * (fy - fz))
    }
}
