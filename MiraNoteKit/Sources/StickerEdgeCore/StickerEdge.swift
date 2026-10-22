import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The white die-cut edge of a generated sticker, drawn by code.
///
/// The image model draws its sticker -- usually with a white rim of its own --
/// on a flat backdrop, and Vision lifts it. Vision is good at *which* thing is
/// the sticker and unreliable at *where* a pale rim ends: on the bench it
/// dropped whole stretches of the model's rim on half the stickers, and on a
/// repainted backdrop it took the model's drop shadow instead. So the roles are
/// split here:
///
/// - Vision picks the sticker (which connected parts count);
/// - the backdrop colour decides where its edge is (the backdrop is flat, so
///   its colour can be keyed, shadow tones included);
/// - and the white rim is redrawn at a uniform width with a smoothed outline,
///   so a rim Vision dropped or the model drew unevenly cannot show as a gap.
///
/// Only the art keeps its colours. The model's own rim, its grey stroke, and
/// any shadow sliver are painted over white, which is what removes the seam
/// line where two whites of slightly different tone would otherwise meet.
///
/// Prototyped in Python against Vision on 14 generated stickers (see
/// miranote-api docs/plans/2026-10-21-sticker-edge-and-speed.md); the
/// constants below are the ones that bench settled on.
public enum StickerEdge {
    public struct Parameters: Sendable {
        /// Corner patch size (px) the backdrop colour is read from.
        public var corner = 16
        /// RGB distance that still counts as backdrop.
        public var backdropDistance = 38.0
        /// The key threshold stays below this share of the backdrop's distance
        /// to white, or a pale backdrop's key eats the model's white rim.
        public var whiteMargin = 0.4
        /// Chromaticity distance for a backdrop shadow (a darker backdrop).
        public var shadowChroma = 0.035
        /// Largest RGB distance a shadow pixel may have from the backdrop.
        public var shadowDistance = 175.0
        /// Corner std above this means the backdrop is not flat: no keying.
        public var uniformMax = 18.0
        /// Enclosed backdrop areas bigger than this share of the image, ringed
        /// by white, are real holes (a mug handle).
        public var holeMinFraction = 0.0015
        /// Vision's mask eroded by this many px is always kept.
        public var trustInset = 16.0
        /// Components smaller than this share of the sticker are dropped.
        public var speckFraction = 0.002
        /// The model's rim: every channel above this...
        public var rimLightMin = 238.0
        /// ...and channel spread below this (rims measure <= 3, a cream body ~19).
        public var rimLightSpread = 10.0
        /// The model rim width estimate is capped at this share of the subject.
        public var rimWidthCapFraction = 0.035
        /// Outermost px checked for backdrop blends and the model's grey stroke.
        public var seamBand = 4.0
        /// Distance from the backdrop-to-white line that counts as a blend.
        public var seamTolerance = 14.0
        /// Art components smaller than this share, at the edge, are shadow slivers.
        public var sliverFraction = 0.003
        /// White rim width as a share of the subject's longer side, and its floor.
        public var rimFraction = 0.022
        public var rimMin = 9
        /// Outline smoothing, as a share of the rim width.
        public var smoothSigmaFraction = 0.35
        /// When the model drew no rim the outline follows the art itself
        /// (feathers, leaves), so it gets a wider rim and more smoothing.
        public var bareRimScale = 1.3
        public var bareSigmaFraction = 0.6

        public init() {}
    }

    public enum Failure: Error, Equatable {
        case undecodable
        case sizeMismatch
        case nothingLifted
        case unencodable
    }

    /// What the rebuild decided, for logs and the bench.
    public struct Report: Sendable, Equatable {
        public var keyed: Bool
        public var modelRimWidth: Int
        public var rimWidth: Int
        public var padding: Int
    }

    /// `raw` is the generated image as it came from the server, `lifted` the
    /// Vision cut-out of it (only its alpha is read). Returns an RGBA PNG,
    /// larger than `raw` by the rim on every side.
    public static func rebuild(raw: Data, lifted: Data,
                               parameters: Parameters = Parameters()) throws -> Data {
        try rebuildReporting(raw: raw, lifted: lifted, parameters: parameters).png
    }

    public static func rebuildReporting(raw: Data, lifted: Data,
                                        parameters: Parameters = Parameters()) throws
        -> (png: Data, report: Report) {
        guard let source = Bitmap(data: raw), let cut = Bitmap(data: lifted) else {
            throw Failure.undecodable
        }
        guard source.width == cut.width, source.height == cut.height else {
            throw Failure.sizeMismatch
        }
        let alpha = (0..<(cut.width * cut.height)).map { cut.pixels[$0 * 4 + 3] }
        let (out, report) = try rebuild(source, liftedAlpha: alpha, parameters)
        guard let png = out.png() else { throw Failure.unencodable }
        return (png, report)
    }

    // MARK: - The pipeline

    static func rebuild(_ raw: Bitmap, liftedAlpha: [UInt8],
                        _ p: Parameters) throws -> (Bitmap, Report) {
        let w = raw.width, h = raw.height, n = w * h
        let vis = liftedAlpha.map { $0 > 127 }
        guard vis.contains(true) else { throw Failure.nothingLifted }
        // A view, not a copy: a Double copy of the image was 24 bytes a pixel,
        // the largest single buffer here.
        let rgb = RGB(pixels: raw.pixels)
        let (backdrop, spread) = Self.backdrop(rgb, w, h, p.corner)
        let keyed = spread <= p.uniformMax
        let mask = keyed ? subjectMask(rgb, w, h, vis, backdrop, p) : vis
        // keyed away entirely (a Vision cut thinner than trustInset, all of it
        // backdrop-coloured): throwing keeps Vision's cut instead of a blank
        guard mask.contains(true) else { throw Failure.nothingLifted }

        // Subject size and the model's own rim
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w where mask[y * w + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let side = Double(max(maxX - minX, maxY - minY))
        let depth = distance(to: mask.map { !$0 }, w, h)
        let light = (0..<n).map { i -> Bool in
            let r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2]
            let lo = min(r, g, b), hi = max(r, g, b)
            return mask[i] && lo > p.rimLightMin && hi - lo < p.rimLightSpread
        }
        let modelRim = modelRimWidth(light: light, mask: mask, depth: depth, side: side, p)

        var rim = max(p.rimMin, Int((p.rimFraction * side).rounded()))
        var sigmaFraction = p.smoothSigmaFraction
        if modelRim == 0 {
            rim = Int((Double(rim) * p.bareRimScale).rounded())
            sigmaFraction = p.bareSigmaFraction
        }
        let sigma = max(1.0, sigmaFraction * Double(rim))

        // Art: what keeps its colours
        let seamBand = Float(p.seamBand)
        var art = (0..<n).map { i in mask[i] && !(light[i] && depth[i] <= Float(modelRim + 1)) }
        if modelRim > 0 {
            // with a model rim, the outermost px are its grey stroke or shadow
            for i in 0..<n where depth[i] <= seamBand { art[i] = false }
        }
        dropSlivers(&art, depth: depth, w, h, limit: Double(modelRim) + p.seamBand, p)
        // art drawn straight onto the backdrop: its outermost px are backdrop blends
        let axis = (255 - backdrop.0, 255 - backdrop.1, 255 - backdrop.2)
        let axisLength2 = max(1e-6, axis.0 * axis.0 + axis.1 * axis.1 + axis.2 * axis.2)
        for i in 0..<n where art[i] && depth[i] <= seamBand {
            let d0 = rgb[i * 3] - backdrop.0, d1 = rgb[i * 3 + 1] - backdrop.1,
                d2 = rgb[i * 3 + 2] - backdrop.2
            let t = min(1, max(0, (d0 * axis.0 + d1 * axis.1 + d2 * axis.2) / axisLength2))
            let e0 = d0 - t * axis.0, e1 = d1 - t * axis.1, e2 = d2 - t * axis.2
            if (e0 * e0 + e1 * e1 + e2 * e2).squareRoot() < p.seamTolerance { art[i] = false }
        }

        // Pad so a subject near the canvas edge still gets its whole rim
        let pad = Int(Double(rim) + 3 * sigma + 2)
        let pw = w + 2 * pad, ph = h + 2 * pad, pn = pw * ph
        func padded(_ a: [Bool]) -> [Bool] {
            var out = [Bool](repeating: false, count: pn)
            for y in 0..<h { for x in 0..<w { out[(y + pad) * pw + x + pad] = a[y * w + x] } }
            return out
        }
        let maskP = padded(mask), artP = padded(art)

        // Outline: open (drops 1-3 px shadow protrusions), round dilation, blur,
        // steep ramp. The art is added back after the opening so a thin part
        // of it -- a stem, a string, an antenna -- still gets its rim.
        let eroded = distance(to: maskP.map { !$0 }, pw, ph).map { $0 > 3 }
        var opened = distance(to: eroded, pw, ph).map { $0 <= 3 }
        for i in 0..<pn where artP[i] { opened[i] = true }
        let rimAlpha = Self.rimAlpha(around: opened, pw, ph, rim: rim, sigma: sigma)
        let artAlpha = gaussian(artP.map { $0 ? 1 : 0 }, pw, ph, sigma: 0.8)

        var out = Bitmap(width: pw, height: ph)
        for y in 0..<ph {
            let sy = min(h - 1, max(0, y - pad))
            for x in 0..<pw {
                let i = y * pw + x
                let sx = min(w - 1, max(0, x - pad))
                let s = (sy * w + sx) * 4
                let a = Double(artAlpha[i])
                for c in 0..<3 {
                    let value = artP[i] ? Double(raw.pixels[s + c]) : 255
                    out.pixels[i * 4 + c] = UInt8((value * a + 255 * (1 - a)).rounded())
                }
                out.pixels[i * 4 + 3] = UInt8((Double(rimAlpha[i]) * 255).rounded())
            }
        }
        return (out, Report(keyed: keyed, modelRimWidth: modelRim, rimWidth: rim, padding: pad))
    }

    /// The rim's alpha: everything within `rim` px of `base` (a round, Euclidean
    /// dilation), Gaussian-blurred and pulled back through a steep ramp so the
    /// edge is smooth but crisp, with `base` itself always opaque.
    static func rimAlpha(around base: [Bool], _ w: Int, _ h: Int,
                         rim: Int, sigma: Double) -> [Float] {
        let outside = distance(to: base, w, h)
        var alpha = outside.map { Float($0 <= Float(rim) ? 1 : 0) }
        alpha = gaussian(alpha, w, h, sigma: Float(sigma))
        for i in 0..<alpha.count {
            alpha[i] = base[i] ? 1 : min(1, max(0, (alpha[i] - 0.5) * 8 + 0.5))
        }
        return alpha
    }

    /// Median of the four corner patches, and their mean per-channel std.
    static func backdrop(_ rgb: RGB, _ w: Int, _ h: Int,
                         _ corner: Int) -> ((Double, Double, Double), Double) {
        let c = max(1, min(corner, w / 4, h / 4))
        var channels: [[Double]] = [[], [], []]
        for (ox, oy) in [(0, 0), (w - c, 0), (0, h - c), (w - c, h - c)] {
            for y in oy..<(oy + c) { for x in ox..<(ox + c) {
                for k in 0..<3 { channels[k].append(rgb[(y * w + x) * 3 + k]) }
            } }
        }
        func median(_ v: [Double]) -> Double {
            let s = v.sorted(), m = s.count / 2
            return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
        }
        func std(_ v: [Double]) -> Double {
            let mean = v.reduce(0, +) / Double(v.count)
            return (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)).squareRoot()
        }
        let spread = (std(channels[0]) + std(channels[1]) + std(channels[2])) / 3
        return ((median(channels[0]), median(channels[1]), median(channels[2])), spread)
    }

    /// Vision picks the parts, the backdrop key places their edge.
    static func subjectMask(_ rgb: RGB, _ w: Int, _ h: Int, _ vis: [Bool],
                            _ bg: (Double, Double, Double), _ p: Parameters) -> [Bool] {
        let n = w * h
        let toWhite = ((255 - bg.0) * (255 - bg.0) + (255 - bg.1) * (255 - bg.1)
                       + (255 - bg.2) * (255 - bg.2)).squareRoot()
        let threshold = min(p.backdropDistance, p.whiteMargin * toWhite)
        let bgSum = bg.0 + bg.1 + bg.2 + 1e-6
        let bgLum = (bg.0 + bg.1 + bg.2) / 3
        var backdropLike = [Bool](repeating: false, count: n)
        var whiteish = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2]
            let d = ((r - bg.0) * (r - bg.0) + (g - bg.1) * (g - bg.1)
                     + (b - bg.2) * (b - bg.2)).squareRoot()
            let sum = r + g + b + 1e-6
            let c0 = r / sum - bg.0 / bgSum, c1 = g / sum - bg.1 / bgSum, c2 = b / sum - bg.2 / bgSum
            let chroma = (c0 * c0 + c1 * c1 + c2 * c2).squareRoot()
            let lum = (r + g + b) / 3
            let shadow = chroma < p.shadowChroma && lum < bgLum && lum > 0.35 * bgLum
                && d < p.shadowDistance
            backdropLike[i] = d < threshold || shadow
            whiteish[i] = min(r, g, b) > p.rimLightMin
        }

        let (labels, count) = label(backdropLike, w, h)
        var border = Set<Int32>()
        for x in 0..<w { border.insert(labels[x]); border.insert(labels[(h - 1) * w + x]) }
        for y in 0..<h { border.insert(labels[y * w]); border.insert(labels[y * w + w - 1]) }
        border.remove(0)
        var sizes = [Int](repeating: 0, count: count + 1)
        var visHits = [Int](repeating: 0, count: count + 1)
        for i in 0..<n where labels[i] > 0 {
            sizes[Int(labels[i])] += 1
            if vis[i] { visHits[Int(labels[i])] += 1 }
        }
        // A big enclosed backdrop-coloured area is a hole (a mug handle) only when
        // Vision also left it out and it is ringed by white: a star filled with
        // the backdrop's colour and ringed by its own blue line is body.
        var holeLabels = Set<Int32>()
        for l in 1...max(1, count) where count > 0 && !border.contains(Int32(l)) {
            guard Double(sizes[l]) > p.holeMinFraction * Double(n),
                  Double(visHits[l]) / Double(sizes[l]) < 0.5 else { continue }
            if ringWhiteShare(labels, Int32(l), whiteish, w, h) >= 0.5 { holeLabels.insert(Int32(l)) }
        }
        let inside = distance(to: vis.map { !$0 }, w, h)
        var candidate = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let l = labels[i]
            let hole = l > 0 && holeLabels.contains(l)
            let exterior = l > 0 && border.contains(l)
            candidate[i] = (!exterior && !hole) || (inside[i] > Float(p.trustInset) && !hole)
        }

        let (parts, partCount) = label(candidate, w, h)
        var partSize = [Int](repeating: 0, count: partCount + 1)
        var picked = [Bool](repeating: false, count: partCount + 1)
        for i in 0..<n where parts[i] > 0 {
            partSize[Int(parts[i])] += 1
            if vis[i] { picked[Int(parts[i])] = true }
        }
        let total = (1..<(partCount + 1)).reduce(0) { picked[$1] ? $0 + partSize[$1] : $0 }
        for l in 1..<(partCount + 1) where picked[l]
            && Double(partSize[l]) < p.speckFraction * Double(total) {
            picked[l] = false
        }
        return parts.map { $0 > 0 && picked[Int($0)] }
    }

    /// Share of white pixels in the 3 px (city-block) ring around one component.
    static func ringWhiteShare(_ labels: [Int32], _ l: Int32, _ whiteish: [Bool],
                               _ w: Int, _ h: Int) -> Double {
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w where labels[y * w + x] == l {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        var ring = 0, white = 0
        for y in max(0, minY - 3)...min(h - 1, maxY + 3) {
            for x in max(0, minX - 3)...min(w - 1, maxX + 3) where labels[y * w + x] != l {
                var near = false
                outer: for dy in -3...3 {
                    let yy = y + dy
                    guard yy >= 0, yy < h else { continue }
                    let reach = 3 - abs(dy)
                    for dx in -reach...reach {
                        let xx = x + dx
                        if xx >= 0, xx < w, labels[yy * w + xx] == l { near = true; break outer }
                    }
                }
                if near { ring += 1; if whiteish[y * w + x] { white += 1 } }
            }
        }
        return ring == 0 ? 0 : Double(white) / Double(ring)
    }

    /// Width of the white rim the model drew itself, 0 if none: read from
    /// depth 4 inward (the outermost px are anti-aliasing or shadow), the first
    /// depth where near-white stops being the majority.
    static func modelRimWidth(light: [Bool], mask: [Bool], depth: [Float],
                              side: Double, _ p: Parameters) -> Int {
        let cap = max(6, Int(p.rimWidthCapFraction * side))
        var inRing = [Int](repeating: 0, count: cap + 1)
        var lightInRing = [Int](repeating: 0, count: cap + 1)
        for i in 0..<mask.count where mask[i] {
            let d = Int(depth[i].rounded(.up))
            guard d >= 1, d <= cap else { continue }
            inRing[d] += 1
            if light[i] { lightInRing[d] += 1 }
        }
        func share(_ d: Int) -> Double {
            inRing[d] == 0 ? 0 : Double(lightInRing[d]) / Double(inRing[d])
        }
        if (4...6).allSatisfy({ share($0) < 0.5 }) { return 0 }
        return (4...cap).first { share($0) < 0.5 } ?? cap
    }

    /// Shadow slivers and dashes clinging to the outside of the model's rim:
    /// small art components that never reach deeper than `limit`.
    static func dropSlivers(_ art: inout [Bool], depth: [Float], _ w: Int, _ h: Int,
                            limit: Double, _ p: Parameters) {
        let (labels, count) = label(art, w, h)
        guard count > 0 else { return }
        var size = [Int](repeating: 0, count: count + 1)
        var deepest = [Float](repeating: 0, count: count + 1)
        for i in 0..<art.count where labels[i] > 0 {
            let l = Int(labels[i])
            size[l] += 1
            deepest[l] = max(deepest[l], depth[i])
        }
        let total = Double(size.reduce(0, +))
        var junk = [Bool](repeating: false, count: count + 1)
        for l in 1...count where Double(size[l]) < p.sliverFraction * total && Double(deepest[l]) <= limit {
            junk[l] = true
        }
        for i in 0..<art.count where labels[i] > 0 && junk[Int(labels[i])] { art[i] = false }
    }

    // MARK: - Image primitives

    /// 4-connected component labels (0 = background) and the label count.
    /// Raw pointers throughout: in a debug build Array subscripts cost ~50x,
    /// and this runs three times per sticker.
    static func label(_ m: [Bool], _ w: Int, _ h: Int) -> ([Int32], Int) {
        let n = m.count
        var labels = [Int32](repeating: 0, count: n)
        var count: Int32 = 0
        let stack = UnsafeMutablePointer<Int>.allocate(capacity: max(1, n))
        defer { stack.deallocate() }
        m.withUnsafeBufferPointer { mb in
            labels.withUnsafeMutableBufferPointer { lb in
                let mp = mb.baseAddress!, lp = lb.baseAddress!
                var next: Int32 = 0
                for start in 0..<n where mp[start] && lp[start] == 0 {
                    next += 1
                    lp[start] = next
                    var top = 0
                    stack[top] = start; top += 1
                    while top > 0 {
                        top -= 1
                        let i = stack[top]
                        let x = i % w
                        if x > 0, mp[i - 1], lp[i - 1] == 0 { lp[i - 1] = next; stack[top] = i - 1; top += 1 }
                        if x < w - 1, mp[i + 1], lp[i + 1] == 0 { lp[i + 1] = next; stack[top] = i + 1; top += 1 }
                        if i >= w, mp[i - w], lp[i - w] == 0 { lp[i - w] = next; stack[top] = i - w; top += 1 }
                        if i + w < n, mp[i + w], lp[i + w] == 0 { lp[i + w] = next; stack[top] = i + w; top += 1 }
                    }
                }
                count = next
            }
        }
        return (labels, Int(count))
    }

    /// Exact Euclidean distance from every pixel to the nearest `feature` pixel
    /// (Felzenszwalb & Huttenlocher, two separable passes). Matches
    /// scipy.ndimage.distance_transform_edt(~feature). Raw pointers for the
    /// same debug-build reason as `label`.
    static func distance(to feature: [Bool], _ w: Int, _ h: Int) -> [Float] {
        let inf = 1e20
        let longest = max(w, h)
        // Float storage, half of Double: squared distances on a sticker stay far
        // below 2^24, so they are exact; the per-row scratch keeps Double.
        var grid = [Float](repeating: 0, count: w * h)
        let f = UnsafeMutablePointer<Double>.allocate(capacity: longest)
        let d = UnsafeMutablePointer<Double>.allocate(capacity: longest)
        let v = UnsafeMutablePointer<Int>.allocate(capacity: longest)
        let z = UnsafeMutablePointer<Double>.allocate(capacity: longest + 1)
        defer { f.deallocate(); d.deallocate(); v.deallocate(); z.deallocate() }
        feature.withUnsafeBufferPointer { fb in
            grid.withUnsafeMutableBufferPointer { gb in
                let fp = fb.baseAddress!, g = gb.baseAddress!
                for i in 0..<(w * h) { g[i] = fp[i] ? 0 : Float(inf) }
                for x in 0..<w {
                    for y in 0..<h { f[y] = Double(g[y * w + x]) }
                    edt1D(f, d, v, z, h, inf)
                    for y in 0..<h { g[y * w + x] = Float(d[y]) }
                }
                for y in 0..<h {
                    let row = g + y * w
                    for x in 0..<w { f[x] = Double(row[x]) }
                    edt1D(f, d, v, z, w, inf)
                    for x in 0..<w { row[x] = Float(d[x].squareRoot()) }
                }
            }
        }
        return grid
    }

    /// One squared-distance pass over `n` samples of `f` into `d`.
    private static func edt1D(_ f: UnsafeMutablePointer<Double>, _ d: UnsafeMutablePointer<Double>,
                              _ v: UnsafeMutablePointer<Int>, _ z: UnsafeMutablePointer<Double>,
                              _ n: Int, _ inf: Double) {
        var k = 0
        v[0] = 0; z[0] = -inf; z[1] = inf
        var q = 1
        while q < n {
            let fq = f[q] + Double(q * q)
            var r = v[k]
            var s = (fq - (f[r] + Double(r * r))) / Double(2 * (q - r))
            while s <= z[k] {
                k -= 1
                r = v[k]
                s = (fq - (f[r] + Double(r * r))) / Double(2 * (q - r))
            }
            k += 1
            v[k] = q; z[k] = s; z[k + 1] = inf
            q += 1
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            let dq = Double(q - v[k])
            d[q] = dq * dq + f[v[k]]
        }
    }

    /// Separable Gaussian, truncated at 4 sigma like scipy, edges replicated
    /// (every caller pads its image, so the edge rule never touches a sticker).
    static func gaussian(_ src: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
        let radius = max(1, Int(4 * sigma + 0.5))
        var kernel = (-radius...radius).map { i in exp(-Float(i * i) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        kernel = kernel.map { $0 / total }
        func blurRows(_ input: [Float], _ cols: Int, _ rows: Int) -> [Float] {
            var output = [Float](repeating: 0, count: input.count)
            var line = [Float](repeating: 0, count: cols + 2 * radius)
            for r in 0..<rows {
                let base = r * cols
                for i in 0..<radius { line[i] = input[base]; line[cols + radius + i] = input[base + cols - 1] }
                for c in 0..<cols { line[radius + c] = input[base + c] }
                line.withUnsafeBufferPointer { l in
                    kernel.withUnsafeBufferPointer { k in
                        output.withUnsafeMutableBufferPointer { o in
                            vDSP_conv(l.baseAddress!, 1, k.baseAddress!, 1,
                                      o.baseAddress! + base, 1,
                                      vDSP_Length(cols), vDSP_Length(kernel.count))
                        }
                    }
                }
            }
            return output
        }
        func transpose(_ input: [Float], _ cols: Int, _ rows: Int) -> [Float] {
            var output = [Float](repeating: 0, count: input.count)
            vDSP_mtrans(input, 1, &output, 1, vDSP_Length(cols), vDSP_Length(rows))
            return output
        }
        let horizontal = blurRows(src, w, h)
        let vertical = blurRows(transpose(horizontal, w, h), h, w)
        return transpose(vertical, h, w)
    }
}

/// An RGBA8 buffer read as interleaved RGB doubles -- `rgb[i * 3 + c]` -- without
/// copying it: the pipeline's colour tests index pixels that way.
struct RGB {
    let pixels: [UInt8]

    @inline(__always) subscript(index: Int) -> Double {
        Double(pixels[(index / 3) * 4 + index % 3])
    }
}

/// Straight (non-premultiplied) RGBA8 pixels.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Decodes any ImageIO format. Alpha is read straight; colour is only
    /// meaningful where alpha is 255, which is everywhere this reads colour.
    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // un-premultiply so colour reads true at partial alpha
        for i in stride(from: 0, to: buffer.count, by: 4) {
            let a = buffer[i + 3]
            if a > 0 && a < 255 {
                for c in 0..<3 {
                    buffer[i + c] = UInt8(min(255, (Int(buffer[i + c]) * 255 + Int(a) / 2) / Int(a)))
                }
            }
        }
        width = w
        height = h
        pixels = buffer
    }

    func png() -> Data? {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
