import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A generated sticker cut out without the model's white die-cut edge.
///
/// The image model draws the art on a flat backdrop that shows through its
/// holes, and Vision lifts it. Stickers come out with no edge (team decision
/// 2026-10-24; Outline adds one on request). Now and then the model still draws
/// a white die-cut rim of its own, and Vision cannot be asked to drop it: it is
/// unreliable at where a pale rim ends. So the roles are split:
///
/// - Vision picks the sticker (which connected parts count) and its holes (an
///   enclosed patch of backdrop it left out);
/// - the backdrop colour moves the outer edge (the backdrop is flat, so its
///   colour can be keyed, shadow tones included), within a few px of Vision's;
/// - and a rim, when there is one, is found by what it is: near-white, joined
///   to the outside, and never further from the coloured art than the rim is
///   wide. A white body behind an outline is not joined to it; one with no
///   outline loses only a band the rim's width.
///
/// With no rim the key may add to Vision's cut but not take from it, since on
/// a pale backdrop pale art (silver, a daisy) reads as backdrop to the key.
///
/// The art keeps its pixels; only its outermost 2 px are un-mixed from the
/// white or backdrop they were blended with, so no pale fringe is left.
///
/// Prototyped in Python against Vision on 24 generated stickers (miranote-api
/// poc/image-generation/test_output/sticker_clean_cut_20261028/clean_cut.py),
/// then tuned in Swift on 100 more drawn with and without the rim
/// (.../sticker_prompt_bench_20261028); the constants below are the ones those
/// benches settled on.
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
        /// Channel spread above which a backdrop is coloured, so a shadow on it
        /// can overrule Vision (bench: grey 15-19, cream 30-37, a light blue or
        /// yellow 104-135).
        public var tintedBackdrop = 40.0
        /// On a coloured backdrop, px this close to it are backdrop wherever
        /// they are (bench, 48 stickers: the art 6 px in from its edge keeps
        /// 36+ away, glasses' see-through lenses the nearest).
        public var backdropExact: Float = 30
        /// Looser shadow test for the contact shadow on a coloured backdrop
        /// (bench: chroma 0.05-0.07, 0.23-0.76 of the backdrop's luminance).
        public var contactShadowChroma = 0.09
        public var contactShadowMinLum = 0.15
        /// Corner std above this means the backdrop is not flat: no keying.
        public var uniformMax = 18.0
        /// Enclosed backdrop areas bigger than this share of the image that
        /// Vision left out are holes (smaller ones are key noise)...
        public var holeMinFraction = 0.00002
        /// ...and, on a rimmed sticker, only those this close to the backdrop on
        /// average (bench holes 2.3-11, a white body's pale shading 12.4-31), or
        /// bigger than `ringedHoleMinFraction` and ringed by white (a mug handle).
        public var flatHoleDistance = 11.5
        public var ringedHoleMinFraction = 0.0015
        /// Vision's mask eroded by this many px is always kept.
        public var trustInset = 16.0
        /// The key may move Vision's edge by this many px...
        public var visionReach: Float = 8
        /// ...and beyond it keeps only px this many key thresholds from the
        /// backdrop.
        public var farFromVisionContrast = 2.0
        /// Components smaller than this share of the sticker are dropped.
        public var speckFraction = 0.002
        /// The model's rim: every channel above this...
        public var rimLightMin = 238.0
        /// ...and channel spread below this (rims measure <= 3, a cream body ~19).
        public var rimLightSpread = 10.0
        /// The first estimate of the model's rim width is capped at this share
        /// of the subject...
        public var rimWidthCapFraction = 0.035
        /// ...and the measured one at this.
        public var rimWidthMaxFraction = 0.08
        /// A "rim" over this share of the subject is the art itself (white line
        /// art); a real rim is 10-30% of it, a thin balloon string's up to ~45%.
        public var rimMaxShare = 0.6
        /// What the rim itself is made of: flat near-white, every channel at
        /// least this and spread at most `rimLikeSpread` (rims measure >= 250,
        /// spread <= 3; a white mug body is a shade off, 247/239).
        public var rimLikeMin = 248.0
        public var rimLikeSpread = 5.0
        /// Rim pixels sit at most the rim width plus this share of it (min 4 px)
        /// from coloured art.
        public var rimToleranceFraction = 0.25
        /// Outermost px checked for backdrop blends and the model's grey stroke.
        public var seamBand = 4.0
        /// Distance from the backdrop-to-white line that counts as a blend,
        /// and how far towards white a blend may go before it is white.
        public var seamTolerance = 14.0
        public var blendMaxShare = 0.9
        /// Non-rim px this close to the rim, in the seam band, are its stroke.
        public var seamReach: Float = 3
        /// A rim component must come this close (px) to the outside.
        public var seedDepth: Float = 7
        /// Art components smaller than this share, at the edge, are shadow slivers.
        public var sliverFraction = 0.003
        /// Light left behind the rim above this share of the subject is a white
        /// body: only a band of the rim's width comes off it.
        public var whiteBodyFraction = 0.01
        /// A flat white backing joining several parts (the stars) is rim:
        /// every channel at least `flatWhiteMin`, spread at most `flatWhiteSpread`,
        /// over `backingFlatShare` of it, and no more than `backingMaxFraction`
        /// of the subject.
        public var flatWhiteMin = 250.0
        public var flatWhiteSpread = 4.0
        public var backingFlatShare = 0.85
        public var backingMaxFraction = 0.15
        /// White running deeper than the rim over more than this share of the
        /// subject: drawn on white paper (bench: stars and sakura 0.14, a
        /// flower card 0.35, a white mug 0.43).
        public var paperDeepFraction = 0.25
        /// Paler than any art: the rim's anti-aliasing and paper texture.
        public var paleMin = 215.0
        public var paleSpread = 12.0
        /// Pockets -- rim-white areas thin art closes off (between ropes, legs,
        /// stems): at least `pocketShare` of their edge lies within
        /// max(`pocketGap`, `pocketGapFraction` x rim width) of the rim or the
        /// outside. Above `smallPocketFraction` of the subject, at least
        /// `pocketLightShare` of a pocket must be rim-light.
        public var pocketGap: Float = 6
        public var pocketGapFraction: Float = 0.2
        public var pocketShare = 0.25
        public var smallPocketFraction = 0.002
        public var pocketLightShare = 0.6
        /// Pocket area deeper than the rim above this share of the subject,
        /// over at least `hatchedPocketCount` pockets, is hatching (a pencil
        /// fox 4.8% over 874, a dandelion 2.9% over 231; every other sticker on
        /// the bench under 0.9%, a balloon's 3 gaps 0.9%): a drawing on paper.
        public var hatchedPocketFraction = 0.02
        /// (watercolour balloons on a white backing: 135, and they go)
        public var hatchedPocketCount = 200
        /// Final parts smaller than this (px) are dropped.
        public var minPartPixels = 20
        /// Px from the art's edge that are un-mixed, and the depth of the art
        /// that supplies their colour.
        public var unmixBand: Float = 2.5
        public var coreDepth: Float = 3
        /// Colours closer than this to what they were blended with are left alone.
        public var unmixMin = 40.0
        /// Anti-aliasing of the art's edge.
        public var antialiasSigma: Float = 0.8
        /// The Outline tool's white edge: this share of the sticker's longer
        /// side (team decision 2026-10-28), never under `outlineMin` px.
        public var outlineFraction = 0.04
        public var outlineMin = 9
        /// Largest image cut (px): the model draws 1024 x 1024; 2048 x 2048
        /// would already use ~200 MB.
        public var maxPixels = 2048 * 2048

        public init() {}
    }

    public enum Failure: Error, Equatable {
        case undecodable
        case sizeMismatch
        case nothingLifted
        case unencodable
        /// Over `maxPixels`: the cut holds dozens of full-size buffers, so
        /// Vision's own cut is used instead of risking the app's memory.
        case tooLarge
    }

    /// What the cut decided, for logs and the bench.
    public struct CleanReport: Sendable, Equatable {
        public var keyed: Bool
        /// Width of the white rim the model drew, 0 if none.
        public var modelRimWidth: Int
        /// Where the cropped result sits in the generated image.
        public var cropX: Int
        public var cropY: Int
        /// Pockets removed, and light pixels kept as a white body.
        public var pockets: Int
        public var whiteBodyPixels: Int
        /// Drawn on white paper (a flower card, a pencil sketch): its white
        /// cannot be told from the rim's, so only the rim's band came off.
        public var drawnOnPaper: Bool
    }

    /// `raw` is the generated image as it came from the server, `lifted` the
    /// Vision cut-out of it (only its alpha is read). Returns an RGBA PNG
    /// cropped to the sticker.
    public static func cleanCut(raw: Data, lifted: Data,
                                parameters: Parameters = Parameters()) throws -> Data {
        try cleanCutReporting(raw: raw, lifted: lifted, parameters: parameters).png
    }

    public static func cleanCutReporting(raw: Data, lifted: Data,
                                         parameters: Parameters = Parameters()) throws
        -> (png: Data, report: CleanReport) {
        guard let source = Bitmap(data: raw), let cut = Bitmap(data: lifted) else {
            throw Failure.undecodable
        }
        guard source.width == cut.width, source.height == cut.height else {
            throw Failure.sizeMismatch
        }
        guard source.width * source.height <= parameters.maxPixels else { throw Failure.tooLarge }
        let alpha = (0..<(cut.width * cut.height)).map { cut.pixels[$0 * 4 + 3] }
        let (out, report) = try cleanCut(source, liftedAlpha: alpha, parameters)
        guard let png = out.png() else { throw Failure.unencodable }
        return (png, report)
    }

    // MARK: - The pipeline

    static func cleanCut(_ raw: Bitmap, liftedAlpha: [UInt8],
                         _ p: Parameters) throws -> (Bitmap, CleanReport) {
        let w = raw.width, h = raw.height, n = w * h
        let vis = liftedAlpha.map { $0 > 127 }
        guard vis.contains(true) else { throw Failure.nothingLifted }
        // A view, not a copy: a Double copy of the image was 24 bytes a pixel,
        // the largest single buffer here.
        let rgb = RGB(pixels: raw.pixels)
        let (backdrop, spread) = Self.backdrop(rgb, w, h, p.corner)
        let keyed = spread <= p.uniformMax
        let keyedMask = keyed ? subjectMask(rgb, w, h, vis, backdrop, p) : nil
        let mask = keyedMask?.rimmed ?? vis
        // keyed away entirely (a Vision cut thinner than trustInset, all of it
        // backdrop-coloured): throwing keeps Vision's cut instead of a blank
        guard mask.contains(true) else { throw Failure.nothingLifted }
        let maskCount = Double(mask.reduce(0) { $1 ? $0 + 1 : $0 })

        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w where mask[y * w + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let side = Double(max(maxX - minX, maxY - minY))
        let depth = distance(to: mask.map { !$0 }, w, h)
        // Float, not Double: these two are per pixel and live through the cut
        var lo = [Float](repeating: 0, count: n), spreadOf = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2]
            lo[i] = Float(min(r, g, b))
            spreadOf[i] = Float(max(r, g, b)) - lo[i]
        }
        let light = (0..<n).map {
            mask[$0] && Double(lo[$0]) > p.rimLightMin && Double(spreadOf[$0]) < p.rimLightSpread
        }

        // The model's rim is the art dilated by its width: every rim pixel lies
        // within that width of coloured art. Measured that way -- outer edge to
        // the nearest deep coloured pixel -- rather than by depth alone, which a
        // white body or a shadow band skews.
        let seamBand = Float(p.seamBand)
        let coloured = (0..<n).map { mask[$0] && !light[$0] && depth[$0] > seamBand + 2 }
        let toColoured = coloured.contains(true)
            ? distance(to: coloured, w, h) : [Float](repeating: .greatestFiniteMagnitude, count: n)
        var rimWidth = modelRimWidth(light: light, mask: mask, depth: depth, side: side, p)
        var bandCount = 0
        var litSums: [Float] = []
        for i in 0..<n where mask[i] && depth[i] > seamBand - 1 && depth[i] <= seamBand + 2 {
            bandCount += 1
            if light[i] { litSums.append(depth[i] + toColoured[i]) }
        }
        if rimWidth > 0 || (bandCount > 0 && Double(litSums.count) > 0.5 * Double(bandCount)), !litSums.isEmpty {
            // capped before it becomes an Int: with no coloured art at all (a
            // sticker of pure white) every sum is the "no art" distance, ~3e38
            rimWidth = Int(min(median(litSums), Float(Int(p.rimWidthMaxFraction * side)))
                .rounded(.toNearestOrEven))
        }

        var art = mask
        var pockets = 0, whiteBody = 0, drawnOnPaper = false
        if rimWidth > 0 {
            let W = Float(rimWidth)
            let tol = max(4, Float(p.rimToleranceFraction) * W)
            let rimLike = (0..<n).map {
                mask[$0] && Double(lo[$0]) >= p.rimLikeMin && Double(spreadOf[$0]) <= p.rimLikeSpread
            }
            var rim = Self.rim(light: light, rimLike: rimLike, depth: depth, toColoured: toColoured,
                               width: W, tolerance: tol, w, h, p)
            let settled = settleWhiteRegions(&rim, light: light, rimLike: rimLike, lo: lo, spread: spreadOf,
                                             depth: depth, width: W, tolerance: tol,
                                             maskCount: maskCount, w, h, p)
            whiteBody = settled.whiteBody
            drawnOnPaper = settled.drawnOnPaper
            // The rim's own anti-aliasing and paper texture: paler-than-art px
            // that touch the rim and sit as close to the art as the rim does.
            // Grown from the rim and kept to its band, so a white body behind
            // an outline is never reached.
            let pale = (0..<n).map {
                mask[$0] && Double(lo[$0]) > p.paleMin && Double(spreadOf[$0]) < p.paleSpread
                    && toColoured[$0] <= W + tol
            }
            let weak = (0..<n).map { pale[$0] && depth[$0] <= W + 2 }
            let (grownLabels, grownCount) = label((0..<n).map { weak[$0] || rim[$0] }, w, h, eight: true)
            var touchesRim = [Bool](repeating: false, count: grownCount + 1)
            for i in 0..<n where rim[i] { touchesRim[Int(grownLabels[i])] = true }
            for i in 0..<n where weak[i] && touchesRim[Int(grownLabels[i])] { rim[i] = true }
            if !settled.drawnOnPaper {
                let beforePockets = rim
                let found = removePockets(&rim, mask: mask, light: light, pale: pale, depth: depth,
                                          width: W, tolerance: tol, maskCount: maskCount, w, h, p)
                pockets = found.count
                // Hatching (a pencil fox, a dandelion's seeds): hundreds of white
                // gaps deep inside the art look like pockets. That much pocket
                // area that deep means a drawing on paper: no pockets, and only
                // the rim's band.
                if Double(found.deepPixels) > p.hatchedPocketFraction * maskCount
                    && found.deepPockets >= p.hatchedPocketCount {
                    rim = (0..<n).map { beforePockets[$0] && depth[$0] <= W + 2 }
                    pockets = 0
                    drawnOnPaper = true
                }
            }
            let rimCount = rim.reduce(0) { $1 ? $0 + 1 : $0 }
            if Double(rimCount) > p.rimMaxShare * maskCount {
                // Most of the sticker reads as rim: it is white line art (bare
                // branches, a pale snowflake), not a rim round art.
                rimWidth = 0
                pockets = 0; whiteBody = 0; drawnOnPaper = false
            } else {
                // the model's grey stroke and shadow just outside the rim
                let toRim = distance(to: rim, w, h)
                for i in 0..<n where rim[i] || (toRim[i] <= p.seamReach && depth[i] <= seamBand + 1) {
                    art[i] = false
                }
            }
        }

        var edgeDepth = depth
        if rimWidth > 0 {
            // the rim's outermost px are blends of it and the backdrop
            let axis = (255 - backdrop.0, 255 - backdrop.1, 255 - backdrop.2)
            let axisLength2 = max(1e-6, axis.0 * axis.0 + axis.1 * axis.1 + axis.2 * axis.2)
            for i in 0..<n where art[i] && depth[i] <= seamBand {
                let d0 = rgb[i * 3] - backdrop.0, d1 = rgb[i * 3 + 1] - backdrop.1,
                    d2 = rgb[i * 3 + 2] - backdrop.2
                let t = min(1, max(0, (d0 * axis.0 + d1 * axis.1 + d2 * axis.2) / axisLength2))
                let e0 = d0 - t * axis.0, e1 = d1 - t * axis.1, e2 = d2 - t * axis.2
                // part way between: a blend. Full white here is art the rim
                // test left alone (a white body with no outline), not a blend.
                if t < p.blendMaxShare, (e0 * e0 + e1 * e1 + e2 * e2).squareRoot() < p.seamTolerance {
                    art[i] = false
                }
            }
        } else if let keyedMask {
            // Art drawn straight onto the backdrop, no rim to take off: the bare
            // mask, and Vision's cut is the better judge of a pale part on a
            // pale backdrop (silver scissors on grey, a daisy on cream), so the
            // key may add to it but not take from it -- except holes and the
            // backdrop's shadow.
            art = keyedMask.bare
            for i in 0..<n where vis[i] && !keyedMask.notSticker[i] { art[i] = true }
            // less the crumbs of rim or paper Vision lifted with it
            art = pickParts(art, vis, w, h, p, keep: keyedMask.clearlyArt)
            edgeDepth = distance(to: art.map { !$0 }, w, h)
        }
        dropSlivers(&art, depth: edgeDepth, w, h, limit: Double(rimWidth) + p.seamBand, p,
                    keep: keyedMask?.clearlyArt)
        // crumbs a removed rim can leave (a rope's last px, a hair tip)
        dropSmallParts(&art, w, h, below: p.minPartPixels)
        guard art.contains(true) else { throw Failure.nothingLifted }

        var (out, alpha) = unmixed(raw, rgb, art: art, backdrop: backdrop, w, h, p)
        // crumbs the un-mixing can split off a thin line
        var solid = alpha.map { $0 > 0.5 }
        let before = solid
        dropSmallParts(&solid, w, h, below: p.minPartPixels)
        var dropped = [Bool](repeating: false, count: n)
        for i in 0..<n where before[i] && !solid[i] { dropped[i] = true }
        if dropped.contains(true) {
            let near = distance(to: dropped, w, h)
            for i in 0..<n where dropped[i] || (near[i] <= 2 && alpha[i] <= 0.5) { alpha[i] = 0 }
        }

        var cx0 = w, cx1 = -1, cy0 = h, cy1 = -1
        for i in 0..<n {
            out.pixels[i * 4 + 3] = UInt8((Double(alpha[i]) * 255).rounded())
            guard out.pixels[i * 4 + 3] > 0 else { continue }
            let x = i % w, y = i / w
            cx0 = min(cx0, x); cx1 = max(cx1, x); cy0 = min(cy0, y); cy1 = max(cy1, y)
        }
        guard cx1 >= 0 else { throw Failure.nothingLifted }
        let cropped = out.cropped(x: cx0, y: cy0, width: cx1 - cx0 + 1, height: cy1 - cy0 + 1)
        return (cropped, CleanReport(keyed: keyed, modelRimWidth: rimWidth, cropX: cx0, cropY: cy0,
                                     pockets: pockets, whiteBodyPixels: whiteBody,
                                     drawnOnPaper: drawnOnPaper))
    }

    /// The rim's flat white joined to the outside, no further from coloured
    /// art than the rim is wide (or no deeper than it), plus the anti-aliasing
    /// round it. Joined through any near-white: texture and anti-aliasing
    /// bridge the rim's flat white.
    static func rim(light: [Bool], rimLike: [Bool], depth: [Float], toColoured: [Float],
                    width W: Float, tolerance tol: Float, _ w: Int, _ h: Int,
                    _ p: Parameters) -> [Bool] {
        let n = w * h
        let eligible = (0..<n).map { light[$0] && (toColoured[$0] <= W + tol || depth[$0] <= W + 2) }
        let (labels, count) = label(eligible, w, h, eight: true)
        var seeded = [Bool](repeating: false, count: count + 1)
        for i in 0..<n where eligible[i] && depth[i] <= p.seedDepth { seeded[Int(labels[i])] = true }
        let joined = (0..<n).map { eligible[$0] && seeded[Int(labels[$0])] }
        let flat = (0..<n).map { joined[$0] && rimLike[$0] }
        let around = dilated(flat, w, h, by: 2)
        return (0..<n).map { flat[$0] || (joined[$0] && around[$0]) }
    }

    /// 8-connected dilation, `by` steps (a (2 by + 1)-px square).
    static func dilated(_ m: [Bool], _ w: Int, _ h: Int, by steps: Int) -> [Bool] {
        var cur = m
        for _ in 0..<steps {
            var next = cur
            for y in 0..<h { for x in 0..<w where !cur[y * w + x] {
                search: for yy in max(0, y - 1)...min(h - 1, y + 1) {
                    for xx in max(0, x - 1)...min(w - 1, x + 1) where cur[yy * w + xx] {
                        next[y * w + x] = true
                        break search
                    }
                }
            } }
            cur = next
        }
        return cur
    }

    /// The light left behind the rim, region by region: a flat white backing
    /// (the stars) joins the rim; a white body (a white mug) keeps all but the
    /// rim's flat white in a band of its width. A sticker drawn on white paper
    /// (a pencil fox, flowers on a card) has white running far inside it that
    /// cannot be told from the rim's, so it gets the same band and no pockets
    /// are guessed at (`drawnOnPaper`).
    static func settleWhiteRegions(_ rim: inout [Bool], light: [Bool], rimLike: [Bool],
                                   lo: [Float], spread: [Float], depth: [Float],
                                   width W: Float, tolerance tol: Float, maskCount: Double,
                                   _ w: Int, _ h: Int, _ p: Parameters)
        -> (whiteBody: Int, drawnOnPaper: Bool) {
        let n = w * h
        let (labels, count) = label(light, w, h, eight: true)
        var touching = [Bool](repeating: false, count: count + 1)
        for i in 0..<n where rim[i] { touching[Int(labels[i])] = true }
        var rest = [Int](repeating: 0, count: count + 1), flatRest = [Int](repeating: 0, count: count + 1)
        var deep = [Int](repeating: 0, count: count + 1), deepRimWhite = [Int](repeating: 0, count: count + 1)
        for i in 0..<n where light[i] {
            let l = Int(labels[i])
            guard touching[l] else { continue }
            if depth[i] > W + tol + 2 {
                deep[l] += 1
                if rimLike[i] { deepRimWhite[l] += 1 }
            }
            guard !rim[i] else { continue }
            rest[l] += 1
            if Double(lo[i]) >= p.flatWhiteMin && Double(spread[i]) <= p.flatWhiteSpread { flatRest[l] += 1 }
        }
        enum Verdict { case keep, backing, band, art }
        var verdict = [Verdict](repeating: .keep, count: count + 1)
        var whiteBody = 0, drawnOnPaper = false
        for l in 1..<(count + 1) where touching[l] {
            if Double(deep[l]) > p.paperDeepFraction * maskCount {
                // White far deeper than any rim, over a quarter of the
                // sticker: the art is white there or drawn on white paper.
                // When that white is the rim's own flat white (a white rabbit
                // with no outline), a rim cannot be told from it, so none is
                // taken: a band off it was a band off the rabbit (ears
                // thinned), while a white rim left on white art reads as the
                // art, not as an edge. A shade off the rim's white (a cream
                // body, paper texture), only the rim's own band comes off.
                verdict[l] = Double(deepRimWhite[l]) > 0.5 * Double(deep[l]) ? .art : .band
                whiteBody += rest[l]
                drawnOnPaper = true
            } else if rest[l] == 0 {
                continue
            } else if Double(flatRest[l]) / Double(rest[l]) >= p.backingFlatShare
                && Double(rest[l]) <= p.backingMaxFraction * maskCount {
                verdict[l] = .backing
            } else if Double(rest[l]) > p.whiteBodyFraction * maskCount {
                verdict[l] = .band
                whiteBody += rest[l]
            }
        }
        for i in 0..<n where labels[i] > 0 {
            switch verdict[Int(labels[i])] {
            case .keep: break
            case .backing: rim[i] = true
            case .band: rim[i] = rimLike[i] && depth[i] <= W + 2
            case .art: rim[i] = false
            }
        }
        return (whiteBody, drawnOnPaper)
    }

    /// Pockets: rim-white areas the rim filled but thin art closes off (the
    /// balloon's ropes, a gap between stems or legs). Most of their edge sits a
    /// line's width from the removed rim, or from the outside; an eye's white
    /// is far from both. Returns how many were removed, and how many of
    /// their pixels lie deeper than the rim.
    static func removePockets(_ rim: inout [Bool], mask: [Bool], light: [Bool], pale: [Bool],
                              depth: [Float], width W: Float, tolerance tol: Float, maskCount: Double,
                              _ w: Int, _ h: Int, _ p: Parameters)
        -> (count: Int, deepPixels: Int, deepPockets: Int) {
        let n = w * h
        guard rim.contains(true) else { return (0, 0, 0) }
        let toRim = distance(to: (0..<n).map { rim[$0] || !mask[$0] }, w, h)
        let candidate = (0..<n).map { (pale[$0] || light[$0]) && mask[$0] && !rim[$0] }
        let (labels, count) = label(candidate, w, h, eight: true)
        guard count > 0 else { return (0, 0, 0) }
        var size = [Int](repeating: 0, count: count + 1), lit = [Int](repeating: 0, count: count + 1)
        for i in 0..<n where labels[i] > 0 {
            size[Int(labels[i])] += 1
            if light[i] { lit[Int(labels[i])] += 1 }
        }
        // each pocket's ring: the px just outside it (8-neighbours)
        let gap = max(p.pocketGap, p.pocketGapFraction * W)
        var ring = [Int](repeating: 0, count: count + 1), near = [Int](repeating: 0, count: count + 1)
        var seen: [Int32] = []
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            guard labels[i] == 0 else { continue }
            seen.removeAll(keepingCapacity: true)
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
                let l = labels[yy * w + xx]
                if l > 0, !seen.contains(l) { seen.append(l) }
            } }
            for l in seen {
                ring[Int(l)] += 1
                if toRim[i] <= gap { near[Int(l)] += 1 }
            }
        } }
        var pocket = [Bool](repeating: false, count: count + 1)
        var removed = 0
        for l in 1..<(count + 1) where ring[l] > 0 {
            let s = Double(size[l])
            if s > p.backingMaxFraction * maskCount { continue }
            if s > p.smallPocketFraction * maskCount && Double(lit[l]) / s < p.pocketLightShare { continue }
            if Double(near[l]) / Double(ring[l]) >= p.pocketShare {
                pocket[l] = true
                removed += 1
            }
        }
        var deepPixels = 0
        var deepIn = [Bool](repeating: false, count: count + 1)
        for i in 0..<n where labels[i] > 0 && pocket[Int(labels[i])] {
            rim[i] = true
            if depth[i] > W + tol + 2 { deepPixels += 1; deepIn[Int(labels[i])] = true }
        }
        return (removed, deepPixels, deepIn.reduce(0) { $1 ? $0 + 1 : $0 })
    }

    /// The art over transparency. Its outermost px are un-mixed: colour from
    /// the nearest core pixel, alpha from where the pixel sits between that
    /// colour and what it was blended with -- the white rim or the backdrop,
    /// whichever explains it better.
    static func unmixed(_ raw: Bitmap, _ rgb: RGB, art: [Bool], backdrop: (Double, Double, Double),
                        _ w: Int, _ h: Int, _ p: Parameters) -> (Bitmap, [Float]) {
        let n = w * h
        var alpha = gaussian(art.map { $0 ? 1 : 0 }, w, h, sigma: p.antialiasSigma)
        let artDepth = distance(to: art.map { !$0 }, w, h)
        // core: deep art, plus the ridge of parts too thin to have any (ropes, whiskers)
        let deep = artDepth.map { $0 >= p.coreDepth }
        let far = deep.contains(true) ? distance(to: deep, w, h).map { $0 > 2 * p.coreDepth } : art
        let peak = maximum3x3(artDepth, w, h)
        var core = (0..<n).map { deep[$0] || (art[$0] && far[$0] && artDepth[$0] >= peak[$0]) }
        if !core.contains(true) { core = art }
        let source = nearest(to: core, w, h)

        var out = Bitmap(width: w, height: h)
        let backgrounds = [(255.0, 255.0, 255.0), backdrop]
        for i in 0..<n {
            let inBand = alpha[i] > 0 && artDepth[i] <= p.unmixBand
            let take = inBand || !art[i]
            let s = Int(source[i])
            let f = (rgb[s * 3], rgb[s * 3 + 1], rgb[s * 3 + 2])
            if inBand {
                let c = (rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2])
                var best = Double.infinity, bestAlpha = 1.0
                for k in backgrounds {
                    let d = (f.0 - k.0, f.1 - k.1, f.2 - k.2)
                    let dd = d.0 * d.0 + d.1 * d.1 + d.2 * d.2
                    guard dd > p.unmixMin * p.unmixMin else { continue }
                    let a = min(1, max(0, ((c.0 - k.0) * d.0 + (c.1 - k.1) * d.1 + (c.2 - k.2) * d.2) / dd))
                    let e = (c.0 - (k.0 + a * d.0), c.1 - (k.1 + a * d.1), c.2 - (k.2 + a * d.2))
                    let res = (e.0 * e.0 + e.1 * e.1 + e.2 * e.2).squareRoot()
                    if res < best { best = res; bestAlpha = a }
                }
                if best.isFinite { alpha[i] = min(alpha[i], Float(bestAlpha)) }
            }
            let c = take ? f : (rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2])
            out.pixels[i * 4] = UInt8(c.0.rounded())
            out.pixels[i * 4 + 1] = UInt8(c.1.rounded())
            out.pixels[i * 4 + 2] = UInt8(c.2.rounded())
        }
        return (out, alpha)
    }

    static func median(_ values: [Float]) -> Float {
        let s = values.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Drops 8-connected parts smaller than `below` px.
    static func dropSmallParts(_ m: inout [Bool], _ w: Int, _ h: Int, below: Int) {
        let (labels, count) = label(m, w, h, eight: true)
        guard count > 0 else { return }
        var size = [Int](repeating: 0, count: count + 1)
        for l in labels where l > 0 { size[Int(l)] += 1 }
        for i in 0..<m.count where labels[i] > 0 && size[Int(labels[i])] < below { m[i] = false }
    }

    /// 3x3 maximum, edges replicated.
    static func maximum3x3(_ src: [Float], _ w: Int, _ h: Int) -> [Float] {
        var out = src
        for y in 0..<h { for x in 0..<w {
            var m = src[y * w + x]
            for yy in max(0, y - 1)...min(h - 1, y + 1) { for xx in max(0, x - 1)...min(w - 1, x + 1) {
                m = max(m, src[yy * w + xx])
            } }
            out[y * w + x] = m
        } }
        return out
    }

    // MARK: - Outline

    /// What `outline` drew: the edge's width, and how far the result reaches
    /// left of the sticker's solid part (the edge plus any faint px).
    public struct OutlineReport: Sendable, Equatable {
        public var width: Int
        public var padding: Int
    }

    /// A white edge round a sticker that is already cut out -- the Outline
    /// tool, on a generated sticker, a photo cut-out or a draft alike. Every
    /// transparent edge gets it, a hole's too, so a donut keeps an empty middle
    /// ringed in white; a gap narrower than two widths fills. A sticker that
    /// already has a white edge gets a second one round it. The sticker keeps
    /// its own colours and soft edge; the result is cropped to it, as the
    /// server's /border was, which this replaces.
    public static func outline(lifted: Data, parameters: Parameters = Parameters()) throws -> Data {
        guard let cut = Bitmap(data: lifted) else { throw Failure.undecodable }
        guard let png = try outline(cut, parameters).0.png() else { throw Failure.unencodable }
        return png
    }

    static func outline(_ cut: Bitmap, _ p: Parameters) throws -> (Bitmap, OutlineReport) {
        let w = cut.width, h = cut.height
        // the solid sticker (sizes the edge) and everything visible (kept)
        var minX = w, maxX = -1, minY = h, maxY = -1
        var vx0 = w, vx1 = -1, vy0 = h, vy1 = -1
        for y in 0..<h { for x in 0..<w {
            let a = cut.pixels[(y * w + x) * 4 + 3]
            guard a > 0 else { continue }
            vx0 = min(vx0, x); vx1 = max(vx1, x); vy0 = min(vy0, y); vy1 = max(vy1, y)
            guard a > 127 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { throw Failure.nothingLifted }
        let side = Double(max(maxX - minX, maxY - minY) + 1)
        let width = max(p.outlineMin, Int((p.outlineFraction * side).rounded()))
        let pad = width + 2

        // Work on the sticker's bounds plus the edge, not the whole canvas: a
        // cut-out is mostly transparent and every pass below is per pixel.
        let ox = vx0 - pad, oy = vy0 - pad
        let cw = vx1 - vx0 + 1 + 2 * pad, ch = vy1 - vy0 + 1 + 2 * pad
        var mask = [Bool](repeating: false, count: cw * ch)
        for y in 0..<ch {
            let sy = y + oy
            guard sy >= 0, sy < h else { continue }
            for x in 0..<cw {
                let sx = x + ox
                if sx >= 0, sx < w, cut.pixels[(sy * w + sx) * 4 + 3] > 127 { mask[y * cw + x] = true }
            }
        }
        // The edge is every px within `width` of the sticker, anti-aliased over
        // one px from the distance itself. (A Gaussian-smoothed edge looked a
        // touch softer but closed holes up to 3.4 widths across, not 2.)
        let toSticker = distance(to: mask, cw, ch)

        var out = Bitmap(width: cw, height: ch)
        var cx0 = cw, cx1 = -1, cy0 = ch, cy1 = -1
        for y in 0..<ch { for x in 0..<cw {
            let i = y * cw + x, sx = x + ox, sy = y + oy
            var a = 0.0
            var colour = (255.0, 255.0, 255.0)
            if sx >= 0, sx < w, sy >= 0, sy < h {
                let s = (sy * w + sx) * 4
                a = Double(cut.pixels[s + 3]) / 255
                colour = (Double(cut.pixels[s]), Double(cut.pixels[s + 1]), Double(cut.pixels[s + 2]))
            }
            let e = mask[i] ? 1 : Double(min(1, max(0, Float(width) + 0.5 - toSticker[i])))
            // the sticker over the white edge ("over"; where there is no edge
            // a faint px keeps its own colour)
            let outA = a + e * (1 - a)
            guard outA > 0 else { continue }
            for k in 0..<3 {
                let c = [colour.0, colour.1, colour.2][k]
                out.pixels[i * 4 + k] = UInt8(min(255, (c * a + 255 * e * (1 - a)) / outA).rounded())
            }
            out.pixels[i * 4 + 3] = UInt8((outA * 255).rounded())
            guard out.pixels[i * 4 + 3] > 0 else { continue }
            cx0 = min(cx0, x); cx1 = max(cx1, x); cy0 = min(cy0, y); cy1 = max(cy1, y)
        } }
        // cropped to what shows: the sticker and its edge, no margin
        let cropped = out.cropped(x: cx0, y: cy0, width: cx1 - cx0 + 1, height: cy1 - cy0 + 1)
        return (cropped, OutlineReport(width: width, padding: minX - (ox + cx0)))
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

    /// Vision picks the parts, the backdrop key places their edge -- two ways.
    ///
    /// `rimmed` is for a sticker the model drew a white rim round: Vision is
    /// unsure where a pale rim or white body ends and often drops part of it, so
    /// the key may bring back anything not joined to the outside, and only an
    /// enclosed backdrop area ringed by white (the rim round a mug's handle) is a
    /// hole -- a star filled with the backdrop's colour inside its own outline is
    /// body.
    ///
    /// `bare` is for art drawn straight onto the backdrop, where the backdrop
    /// shows through every hole (a donut's, a key's bow, between spokes or
    /// leaves): an enclosed backdrop area Vision left out is a hole whatever
    /// rings it, and away from Vision's cut only px clearly unlike the backdrop
    /// come back (a string Vision dropped), never a vignette the key misses (a
    /// slab between a tree's branches).
    ///
    /// `notSticker` is what is surely not sticker even where Vision took it:
    /// those holes, and on a coloured backdrop its shadow joined to the outside.
    static func subjectMask(_ rgb: RGB, _ w: Int, _ h: Int, _ vis: [Bool],
                            _ bg: (Double, Double, Double), _ p: Parameters)
        -> (rimmed: [Bool], bare: [Bool], notSticker: [Bool], clearlyArt: [Bool]) {
        let n = w * h
        let toWhite = ((255 - bg.0) * (255 - bg.0) + (255 - bg.1) * (255 - bg.1)
                       + (255 - bg.2) * (255 - bg.2)).squareRoot()
        let threshold = min(p.backdropDistance, p.whiteMargin * toWhite)
        let bgSum = bg.0 + bg.1 + bg.2 + 1e-6
        let bgLum = (bg.0 + bg.1 + bg.2) / 3
        var backdropLike = [Bool](repeating: false, count: n)
        var unlikeBackdrop = [Bool](repeating: false, count: n)
        var shadowLike = [Bool](repeating: false, count: n)
        var whiteish = [Bool](repeating: false, count: n)
        var toBackdrop = [Float](repeating: 0, count: n)
        var softShadow = [Bool](repeating: false, count: n)
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
            unlikeBackdrop[i] = !shadow && d > p.farFromVisionContrast * threshold
            shadowLike[i] = shadow
            whiteish[i] = min(r, g, b) > p.rimLightMin
            toBackdrop[i] = Float(d)
            softShadow[i] = chroma < p.contactShadowChroma && lum < bgLum
                && lum > p.contactShadowMinLum * bgLum && d < p.shadowDistance
        }

        let (labels, count) = label(backdropLike, w, h)
        var border = Set<Int32>()
        for x in 0..<w { border.insert(labels[x]); border.insert(labels[(h - 1) * w + x]) }
        for y in 0..<h { border.insert(labels[y * w]); border.insert(labels[y * w + w - 1]) }
        border.remove(0)
        var sizes = [Int](repeating: 0, count: count + 1)
        var visHits = [Int](repeating: 0, count: count + 1)
        var dSum = [Double](repeating: 0, count: count + 1)
        // every component's bounding box in this one pass, for ringWhiteShare
        var boxes = [(minX: Int, maxX: Int, minY: Int, maxY: Int)](repeating: (w, -1, h, -1), count: count + 1)
        for i in 0..<n where labels[i] > 0 {
            let l = Int(labels[i])
            sizes[l] += 1
            if vis[i] { visHits[l] += 1 }
            dSum[l] += Double(toBackdrop[i])
            let x = i % w, y = i / w
            boxes[l] = (min(boxes[l].minX, x), max(boxes[l].maxX, x), min(boxes[l].minY, y), max(boxes[l].maxY, y))
        }
        var holes = Set<Int32>(), ringedHoles = Set<Int32>()
        for l in 1...max(1, count) where count > 0 && !border.contains(Int32(l)) {
            guard Double(sizes[l]) > p.holeMinFraction * Double(n) else { continue }
            // Vision fills small enclosed gaps (a donut's hole, between spokes)
            // as often as it leaves them: a patch that is the backdrop's own
            // flat colour is a hole whatever Vision did.
            let flat = Double(dSum[l]) / Double(sizes[l]) <= p.flatHoleDistance
            guard flat || Double(visHits[l]) / Double(sizes[l]) < 0.5 else { continue }
            holes.insert(Int32(l))
            // On a rimmed sticker: the backdrop itself showing through (flat,
            // its own colour), or a hole ringed by the rim's white; not the pale
            // shading of a white body that the key happens to catch.
            if Double(dSum[l]) / Double(sizes[l]) <= p.flatHoleDistance
                || (Double(sizes[l]) > p.ringedHoleMinFraction * Double(n)
                    && ringWhiteShare(labels, Int32(l), boxes[l], whiteish, w, h) >= 0.5) {
                ringedHoles.insert(Int32(l))
            }
        }
        let inside = distance(to: vis.map { !$0 }, w, h)
        let toVision = distance(to: vis, w, h)
        // A shadow can be told from art only on a coloured backdrop: on grey or
        // cream, silver scissors and a daisy's shading look like shadow too. On
        // one, the contact shadow the model still draws under the art (a darker,
        // slightly shifted shade of the backdrop, joined to the outside) is
        // never added back where Vision left it out; where Vision took it, it is
        // too like a dark part in the backdrop's hue to take away.
        let tinted = max(bg.0, bg.1, bg.2) - min(bg.0, bg.1, bg.2) > p.tintedBackdrop
        var outerShadow = [Bool](repeating: false, count: n)
        if tinted {
            let (shade, _) = label((0..<n).map { backdropLike[$0] || softShadow[$0] }, w, h)
            var outer = Set<Int32>()
            for x in 0..<w { outer.insert(shade[x]); outer.insert(shade[(h - 1) * w + x]) }
            for y in 0..<h { outer.insert(shade[y * w]); outer.insert(shade[y * w + w - 1]) }
            outer.remove(0)
            for i in 0..<n where (softShadow[i] || shadowLike[i]) && outer.contains(shade[i]) {
                outerShadow[i] = true
            }
        }
        var rimmed = [Bool](repeating: false, count: n)
        var bare = [Bool](repeating: false, count: n)
        var notSticker = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let l = labels[i]
            let hole = l > 0 && holes.contains(l)
            let exterior = l > 0 && border.contains(l)
            let trusted = inside[i] > Float(p.trustInset)
            let reached = toVision[i] <= p.visionReach || unlikeBackdrop[i]
            // The backdrop's own flat colour, on a coloured backdrop (which the
            // prompt keeps out of the art): never sticker, even where Vision
            // took it in -- the gaps between a bare tree's twigs, a birdcage's
            // bars, a dreamcatcher's web.
            let backdrop = tinted && toBackdrop[i] < p.backdropExact
            notSticker[i] = hole || backdrop || (exterior && shadowLike[i] && tinted)
            rimmed[i] = !(l > 0 && ringedHoles.contains(l)) && (!exterior || trusted)
            // the key never adds a contact shadow Vision left out
            bare[i] = !hole && !backdrop && !(outerShadow[i] && !vis[i])
                && ((!exterior && reached) || trusted)
        }
        // clearly coloured art: far from the backdrop, not white, not shadow
        let clearlyArt = (0..<n).map { unlikeBackdrop[$0] && !whiteish[$0] }
        return (pickParts(rimmed, vis, w, h, p), pickParts(bare, vis, w, h, p, keep: clearlyArt),
                notSticker, clearlyArt)
    }

    /// The candidate's components that Vision touched, less specks. With
    /// `keep`, a small part that is mostly `keep` px (clearly coloured art: a
    /// sparkle, a sweat drop, a music note) is not a speck.
    static func pickParts(_ candidate: [Bool], _ vis: [Bool], _ w: Int, _ h: Int,
                          _ p: Parameters, keep: [Bool]? = nil) -> [Bool] {
        let n = w * h
        let (parts, partCount) = label(candidate, w, h)
        var partSize = [Int](repeating: 0, count: partCount + 1)
        var kept = [Int](repeating: 0, count: partCount + 1)
        var picked = [Bool](repeating: false, count: partCount + 1)
        for i in 0..<n where parts[i] > 0 {
            partSize[Int(parts[i])] += 1
            if vis[i] { picked[Int(parts[i])] = true }
            if keep?[i] == true { kept[Int(parts[i])] += 1 }
        }
        let total = (1..<(partCount + 1)).reduce(0) { picked[$1] ? $0 + partSize[$1] : $0 }
        for l in 1..<(partCount + 1) where picked[l]
            && Double(partSize[l]) < p.speckFraction * Double(total)
            && !(keep != nil && 2 * kept[l] >= partSize[l]) {
            picked[l] = false
        }
        return parts.map { $0 > 0 && picked[Int($0)] }
    }

    /// Share of white pixels in the 3 px (city-block) ring around one component.
    static func ringWhiteShare(_ labels: [Int32], _ l: Int32, _ box: (minX: Int, maxX: Int, minY: Int, maxY: Int),
                               _ whiteish: [Bool], _ w: Int, _ h: Int) -> Double {
        let (minX, maxX, minY, maxY) = box
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
                            limit: Double, _ p: Parameters, keep: [Bool]? = nil) {
        let (labels, count) = label(art, w, h)
        guard count > 0 else { return }
        var size = [Int](repeating: 0, count: count + 1)
        var kept = [Int](repeating: 0, count: count + 1)
        var deepest = [Float](repeating: 0, count: count + 1)
        for i in 0..<art.count where labels[i] > 0 {
            let l = Int(labels[i])
            size[l] += 1
            deepest[l] = max(deepest[l], depth[i])
            if keep?[i] == true { kept[l] += 1 }
        }
        let total = Double(size.reduce(0, +))
        var junk = [Bool](repeating: false, count: count + 1)
        // a thin line of clearly coloured art (a motion line) is not a sliver
        for l in 1...count where Double(size[l]) < p.sliverFraction * total && Double(deepest[l]) <= limit
            && !(keep != nil && 2 * kept[l] >= size[l]) {
            junk[l] = true
        }
        for i in 0..<art.count where labels[i] > 0 && junk[Int(labels[i])] { art[i] = false }
    }

    // MARK: - Image primitives

    /// Connected component labels (0 = background) and the label count;
    /// 4-connected, or 8-connected when `eight`.
    /// Raw pointers throughout: in a debug build Array subscripts cost ~50x,
    /// and this runs several times per sticker.
    static func label(_ m: [Bool], _ w: Int, _ h: Int, eight: Bool = false) -> ([Int32], Int) {
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
                        guard eight else { continue }
                        if x > 0, i >= w, mp[i - w - 1], lp[i - w - 1] == 0 {
                            lp[i - w - 1] = next; stack[top] = i - w - 1; top += 1
                        }
                        if x < w - 1, i >= w, mp[i - w + 1], lp[i - w + 1] == 0 {
                            lp[i - w + 1] = next; stack[top] = i - w + 1; top += 1
                        }
                        if x > 0, i + w < n, mp[i + w - 1], lp[i + w - 1] == 0 {
                            lp[i + w - 1] = next; stack[top] = i + w - 1; top += 1
                        }
                        if x < w - 1, i + w < n, mp[i + w + 1], lp[i + w + 1] == 0 {
                            lp[i + w + 1] = next; stack[top] = i + w + 1; top += 1
                        }
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

    /// Index of the nearest `feature` pixel to every pixel (Euclidean, same
    /// two separable passes as `distance`, keeping the argmin). `feature`
    /// must not be empty.
    static func nearest(to feature: [Bool], _ w: Int, _ h: Int) -> [Int32] {
        let inf = 1e20
        let longest = max(w, h)
        var columnD = [Double](repeating: 0, count: w * h)
        var columnRow = [Int32](repeating: 0, count: w * h)
        var out = [Int32](repeating: 0, count: w * h)
        let f = UnsafeMutablePointer<Double>.allocate(capacity: longest)
        let d = UnsafeMutablePointer<Double>.allocate(capacity: longest)
        let a = UnsafeMutablePointer<Int>.allocate(capacity: longest)
        let v = UnsafeMutablePointer<Int>.allocate(capacity: longest)
        let z = UnsafeMutablePointer<Double>.allocate(capacity: longest + 1)
        defer { f.deallocate(); d.deallocate(); a.deallocate(); v.deallocate(); z.deallocate() }
        for x in 0..<w {
            for y in 0..<h { f[y] = feature[y * w + x] ? 0 : inf }
            edt1D(f, d, v, z, h, inf, argmin: a)
            for y in 0..<h { columnD[y * w + x] = d[y]; columnRow[y * w + x] = Int32(a[y]) }
        }
        for y in 0..<h {
            for x in 0..<w { f[x] = columnD[y * w + x] }
            edt1D(f, d, v, z, w, inf, argmin: a)
            for x in 0..<w { out[y * w + x] = columnRow[y * w + a[x]] * Int32(w) + Int32(a[x]) }
        }
        return out
    }

    /// One squared-distance pass over `n` samples of `f` into `d`.
    /// With `argmin`, also the sample each distance was measured to.
    private static func edt1D(_ f: UnsafeMutablePointer<Double>, _ d: UnsafeMutablePointer<Double>,
                              _ v: UnsafeMutablePointer<Int>, _ z: UnsafeMutablePointer<Double>,
                              _ n: Int, _ inf: Double, argmin: UnsafeMutablePointer<Int>? = nil) {
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
            argmin?[q] = v[k]
        }
    }

    /// Separable Gaussian, truncated at 4 sigma like scipy, edges replicated
    /// (art touching the image's border sees its own edge px repeated).
    /// A sigma under 0.1 is taken as 0.1 rather than dividing by zero.
    static func gaussian(_ src: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
        let sigma = max(0.1, sigma)
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
        // Upright, as Vision and the canvas see it: a photo's EXIF orientation
        // is applied (a full-size "thumbnail" with the transform), so a phone
        // photo stored sideways is not outlined or cut sideways.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pw = properties[kCGImagePropertyPixelWidth] as? Int,
              let ph = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(pw, ph),
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
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

    func cropped(x: Int, y: Int, width cw: Int, height ch: Int) -> Bitmap {
        var out = Bitmap(width: cw, height: ch)
        for row in 0..<ch {
            let from = ((y + row) * width + x) * 4
            out.pixels.replaceSubrange((row * cw * 4)..<((row + 1) * cw * 4),
                                       with: pixels[from..<(from + cw * 4)])
        }
        return out
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
