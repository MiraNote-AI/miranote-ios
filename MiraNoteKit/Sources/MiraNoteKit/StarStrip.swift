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

/// A star's paper strip, cut from a snapshot of its page (#206, the
/// "colorful-D" method of the strip experiment): of every band as long as
/// the page is wide and a sixth as thick, turned 30 degrees either way,
/// the one whose colors vary most. One contiguous cut, so the star is
/// literally a strip of its page. Wound around the star's ten facets, it
/// is the star's face.
public enum StarStrip {
    /// A band on the page: its middle, its turn in radians (y down, so a
    /// positive turn runs down to the right), and its size in pixels.
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
    static let angles = [Double.pi / 6, -Double.pi / 6]

    /// The most colorful band of `page`: the largest variance of CIELAB
    /// a* plus b* over a coarse grid along it.
    public static func colorfulCut(in page: StarPixels) -> Cut {
        let length = Double(page.width)
        let thickness = length / 6
        var best: (score: Double, cut: Cut)?
        for angle in angles {
            let half = abs(sin(angle)) * length / 2 + thickness / 2
            var centerY = half
            while centerY <= Double(page.height) - half + 1 {
                let cut = Cut(centerX: length / 2, centerY: centerY, angle: angle, length: length, thickness: thickness)
                var greenRed: [Double] = [], blueYellow: [Double] = []
                sample(cut, in: page, across: 6, along: 36) { column, row in
                    let lab = Self.lab(page.color(Int(column), Int(row)))
                    greenRed.append(lab.greenRed)
                    blueYellow.append(lab.blueYellow)
                }
                let score = variance(greenRed) + variance(blueYellow)
                if score > best?.score ?? -1 { best = (score, cut) }
                centerY += 4
            }
        }
        // A page shorter than a band still has its middle.
        return best?.cut ?? Cut(centerX: length / 2, centerY: Double(page.height) / 2, angle: angles[0],
                                length: length, thickness: thickness)
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

    /// The strip wound around a five-point star `side` pixels square: its
    /// length runs clockwise from the top tip around the ten facets, its
    /// thickness from the middle out to the edge. Facets alternate a
    /// little darker and lighter, and darken toward the edge, as folded
    /// paper does. The square is filled; the star's outline clips it. The
    /// star's middle sits 4% low, as `RoundedStar` draws it.
    public static func wrap(_ strip: StarPixels, side: Int) -> StarPixels {
        var face = StarPixels(width: side, height: side, fill: StarColor(0, 0, 0))
        let outer = Double(side) / 2
        let inner = outer * 0.5
        let middleX = Double(side) / 2, middleY = Double(side) * 0.54
        let facet = Double.pi / 5
        for row in 0..<side {
            for column in 0..<side {
                let dx = Double(column) + 0.5 - middleX, dy = Double(row) + 0.5 - middleY
                let turn = (atan2(dx, -dy) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
                let index = Int(turn / facet) % 10
                let within = turn / facet - floor(turn / facet)
                // Where this ray meets the star's edge: on the segment
                // from this facet's first vertex to its second.
                let first = index.isMultiple(of: 2) ? outer : inner
                let second = index.isMultiple(of: 2) ? inner : outer
                let start = CGPoint(x: first * sin(Double(index) * facet), y: -first * cos(Double(index) * facet))
                let edgeX = second * sin(Double(index + 1) * facet) - start.x
                let edgeY = -second * cos(Double(index + 1) * facet) - start.y
                let edge = (start.x * edgeY - start.y * edgeX) / (sin(turn) * edgeY + cos(turn) * edgeX)
                let reach = min(1, hypot(dx, dy) / edge)
                let along = (Double(index) + within) / 10 * Double(strip.width - 1)
                let color = bilinear(strip, along, reach * Double(strip.height - 1))
                let shade = (index.isMultiple(of: 2) ? 0.92 : 1.06) * (1 - 0.1 * reach * reach)
                face.set(column, row, color.scaled(shade))
            }
        }
        return face
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
