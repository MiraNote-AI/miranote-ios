import XCTest
@testable import MiraNoteKit
@testable import StickerEdgeCore

/// StickerEdge.cleanCut on drawn inputs whose right answer is known by
/// construction: a red disc inside a white model rim on a flat backdrop, and a
/// "Vision" alpha that gets it wrong in the ways the bench saw Vision get it wrong.
final class StickerEdgeTests: XCTestCase {
    private let size = 240
    private let backdrop: (UInt8, UInt8, UInt8) = (120, 170, 200)
    private let rimWhite: (UInt8, UInt8, UInt8) = (253, 253, 253)
    private let red: (UInt8, UInt8, UInt8) = (210, 40, 40)
    private let ink: (UInt8, UInt8, UInt8) = (40, 30, 30)

    /// Paints every pixel by `colour(x, y)`; nil leaves the backdrop.
    private func picture(_ colour: (Double, Double) -> (UInt8, UInt8, UInt8)?) -> Bitmap {
        var b = Bitmap(width: size, height: size)
        for y in 0..<size { for x in 0..<size {
            let c = colour(Double(x), Double(y)) ?? backdrop
            let i = (y * size + x) * 4
            b.pixels[i] = c.0; b.pixels[i + 1] = c.1; b.pixels[i + 2] = c.2; b.pixels[i + 3] = 255
        } }
        return b
    }

    private func alpha(_ keep: (Double, Double) -> Bool) -> Bitmap {
        var b = Bitmap(width: size, height: size)
        for y in 0..<size { for x in 0..<size where keep(Double(x), Double(y)) {
            let i = (y * size + x) * 4
            b.pixels[i] = 255; b.pixels[i + 1] = 255; b.pixels[i + 2] = 255; b.pixels[i + 3] = 255
        } }
        return b
    }

    private func r(_ x: Double, _ y: Double, _ cx: Double = 120, _ cy: Double = 120) -> Double {
        ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
    }

    /// A red disc of radius 60 inside a white model rim out to 70 -- a rim
    /// 7% of the sticker, as the model draws them (3.5-6% on the bench).
    private func sticker(_ x: Double, _ y: Double) -> (UInt8, UInt8, UInt8)? {
        let d = r(x, y)
        if d <= 60 { return red }
        if d <= 70 { return rimWhite }
        return nil
    }

    private func run(_ raw: Bitmap, _ lifted: Bitmap) throws -> (Bitmap, StickerEdge.CleanReport) {
        let out = try StickerEdge.cleanCutReporting(raw: raw.png()!, lifted: lifted.png()!)
        return (Bitmap(data: out.png)!, out.report)
    }

    /// Pixel of `out` at raw coordinates (x, y); transparent outside the crop.
    private func at(_ out: Bitmap, _ report: StickerEdge.CleanReport, _ x: Int, _ y: Int) -> [UInt8] {
        let ox = x - report.cropX, oy = y - report.cropY
        guard ox >= 0, oy >= 0, ox < out.width, oy < out.height else { return [0, 0, 0, 0] }
        let i = (oy * out.width + ox) * 4
        return Array(out.pixels[i..<(i + 4)])
    }

    func testTheModelsRimIsRemoved() throws {
        let (out, report) = try run(picture(sticker), alpha { x, y in self.r(x, y) <= 70 })

        XCTAssertTrue(report.keyed)
        XCTAssertEqual(report.modelRimWidth, 10, accuracy: 2, "the rim is measured")
        XCTAssertEqual(at(out, report, 120 - 65, 120)[3], 0, "the rim is gone")
        XCTAssertEqual(at(out, report, 120 + 68, 120)[3], 0)
        XCTAssertEqual(at(out, report, 120 - 55, 120)[3], 255, "the art is not")
    }

    func testARimVisionDroppedIsRemovedToo() throws {
        // Vision keeps the disc but loses the rim on the whole left half.
        let lifted = alpha { x, y in self.r(x, y) <= 60 || (self.r(x, y) <= 70 && x > 120) }
        let (out, report) = try run(picture(sticker), lifted)
        XCTAssertEqual(at(out, report, 120 - 65, 120)[3], 0)
        XCTAssertEqual(at(out, report, 120 + 65, 120)[3], 0)
    }

    func testTheArtKeepsItsColours() throws {
        let (out, report) = try run(picture(sticker), alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertEqual(at(out, report, 120, 120), [210, 40, 40, 255])
        let edge = at(out, report, 120 - 59, 120)
        // (a partly transparent px reads back +-1 through the PNG)
        XCTAssertEqual(Int(edge[1]), 40, accuracy: 2, "no white fringe where the rim was: \(edge)")
        XCTAssertEqual(Int(edge[2]), 40, accuracy: 2)
    }

    func testTheOutputIsCroppedToTheArt() throws {
        let (out, report) = try run(picture(sticker), alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertLessThanOrEqual(out.width, 126, "no padding, no rim (141 with it)")
        XCTAssertGreaterThanOrEqual(out.width, 118)
        XCTAssertEqual(report.cropX, 120 - out.width / 2, accuracy: 2)
    }

    func testAHoleRingedByWhiteStaysAHole() throws {
        // A mug handle: backdrop showing through, the model's rim all round it.
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 14 { return nil }
            if d <= 24 { return self.rimWhite }
            return self.sticker(x, y)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) > 14 && self.r(x, y) <= 70 })
        XCTAssertEqual(at(out, report, 120, 120)[3], 0)
        XCTAssertEqual(at(out, report, 120 + 19, 120)[3], 0, "and the rim round the hole goes too")
    }

    func testAHoleRingedByArtIsEmpty() throws {
        // A donut drawn straight on the backdrop: no rim anywhere, the backdrop
        // showing through the hole, and Vision leaving the hole out.
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 20 { return nil }
            if d <= 26 { return self.ink }
            return d <= 60 ? self.red : nil
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) > 20 && self.r(x, y) <= 60 })
        XCTAssertEqual(report.modelRimWidth, 0)
        XCTAssertEqual(at(out, report, 120, 120)[3], 0, "the hole is empty")
        XCTAssertEqual(at(out, report, 120 + 23, 120)[3], 255, "its ring is not")
    }

    func testAPartAShadeOffTheBackdropVisionKeptIsBody() throws {
        // A whale's belly a shade off the backdrop's blue, ringed by its
        // outline: Vision keeps it, so it is body, not a hole. (In the
        // backdrop's exact colour it would go: the prompt keeps that colour
        // out of the art, so there it is backdrop seen through a hole.)
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 30 { return (95, 140, 185) }
            if d <= 36 { return (40, 60, 140) }
            return self.sticker(x, y)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertEqual(at(out, report, 120, 120)[3], 255, "the belly is not punched out")
    }

    func testAHoleVisionFilledOnARimmedStickerOpensWithItsRim() throws {
        // The model drew its rim round the art and round the hole, where the
        // backdrop shows; Vision took the whole disc, hole and all.
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 18 { return nil }
            if d <= 26 { return self.rimWhite }
            return self.sticker(x, y)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertGreaterThan(report.modelRimWidth, 0)
        XCTAssertEqual(at(out, report, 120, 120)[3], 0, "the hole opens")
        XCTAssertEqual(at(out, report, 120 + 22, 120)[3], 0, "and its rim goes with it")
        XCTAssertEqual(at(out, report, 120 + 40, 120)[3], 255, "the art stays")
    }

    func testAHoleVisionFilledOnAGreyBackdropOpens() throws {
        // Bare art on grey (where Vision has the last word on pale parts): a
        // patch of the backdrop's own flat grey ringed by the art is a hole
        // even though Vision took it.
        let grey: (UInt8, UInt8, UInt8) = (170, 170, 170)
        let raw = picture { x, y in
            let d = self.r(x, y)
            return d <= 20 || d > 60 ? grey : self.red
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 60 })
        XCTAssertEqual(at(out, report, 120, 120)[3], 0, "the hole opens")
        XCTAssertEqual(at(out, report, 120 + 40, 120)[3], 255)
    }

    func testSmallColouredPartsVisionKeptStay() throws {
        // A big disc with a sparkle and a short motion line beside it, all
        // taken by Vision: small, but clearly coloured art, not crumbs.
        let blue: (UInt8, UInt8, UInt8) = (40, 60, 210)
        let sparkle: (Double, Double) -> Bool = { x, y in self.r(x, y, 231, 120) <= 3.5 }
        let line: (Double, Double) -> Bool = { x, y in x >= 228 && x <= 230 && y >= 150 && y < 180 }
        let raw = picture { x, y in
            if self.r(x, y) <= 100 { return self.red }
            return sparkle(x, y) || line(x, y) ? blue : nil
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 100 || sparkle(x, y) || line(x, y) })
        XCTAssertEqual(report.modelRimWidth, 0)
        XCTAssertGreaterThan(at(out, report, 231, 120)[3], 200, "the sparkle stays")
        XCTAssertGreaterThan(at(out, report, 229, 165)[3], 150, "the motion line stays")
    }

    func testAnImageOverTheSizeLimitThrows() {
        var p = StickerEdge.Parameters()
        p.maxPixels = 100
        XCTAssertThrowsError(try StickerEdge.cleanCut(raw: picture(sticker).png()!,
                                                      lifted: alpha { _, _ in true }.png()!, parameters: p)) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .tooLarge)
        }
    }

    func testTheBackdropBetweenTwigsGoesEvenWhereVisionTookIt() throws {
        // A bare tree: dark twigs over the backdrop, so dense that Vision
        // takes the whole crown, backdrop and all. The backdrop is the
        // prompt's colour, kept out of the art, so it goes wherever it is.
        let twig: (Double, Double) -> Bool = { x, y in
            Int(x) % 12 < 3 || Int(y) % 12 < 3
        }
        let raw = picture { x, y in
            self.r(x, y) <= 70 && twig(x, y) ? self.ink : nil
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertEqual(report.modelRimWidth, 0)
        XCTAssertEqual(at(out, report, 127, 127)[3], 0, "the gap between twigs is empty")
        XCTAssertGreaterThan(at(out, report, 121, 127)[3], 200, "the twig stays")
    }

    func testABackdropToneVisionLeftOutIsNotAdded() throws {
        // Thin dark branches round a patch of slightly different backdrop (a
        // vignette the key misses): Vision takes only the branches, and the
        // patch must not come back as a slab.
        let branch: (Double, Double) -> Bool = { x, y in
            abs(x - 60) <= 2 || abs(x - 180) <= 2 || abs(y - 60) <= 2 || abs(y - 180) <= 2
        }
        let inBox: (Double, Double) -> Bool = { x, y in x > 58 && x < 182 && y > 58 && y < 182 }
        let raw = picture { x, y in
            guard inBox(x, y) else { return nil }
            return branch(x, y) ? self.ink : (150, 200, 230)
        }
        let (out, report) = try run(raw, alpha { x, y in inBox(x, y) && branch(x, y) })
        XCTAssertEqual(at(out, report, 120, 120)[3], 0, "no slab between the branches")
        // (a 5 px line is anti-aliased right across, so not quite 255)
        XCTAssertGreaterThan(at(out, report, 60, 120)[3], 240, "the branch stays")
    }

    func testWhiteLineArtIsNotTakenForARim() throws {
        // Bare white branches on the backdrop: near-white all through, so the
        // rim test reads most of the sticker as rim. It is the art.
        let branch: (Double, Double) -> Bool = { x, y in
            (abs(x - 120) <= 4 && y > 40 && y < 200) || (abs(y - 90) <= 4 && x > 50 && x < 190)
                || (abs(y - 150) <= 4 && x > 70 && x < 170)
        }
        let raw = picture { x, y in branch(x, y) ? self.rimWhite : nil }
        let (out, report) = try run(raw, alpha { x, y in branch(x, y) })
        XCTAssertEqual(report.modelRimWidth, 0)
        XCTAssertGreaterThan(at(out, report, 120, 120)[3], 240, "the trunk stays")
        XCTAssertGreaterThan(at(out, report, 60, 90)[3], 240, "and its branches")
    }

    func testAPalePartVisionKeptStaysOnBareArt() throws {
        // A red disc with a fringe a shade off a grey backdrop (silver on grey,
        // a daisy on cream): the key reads the fringe as backdrop, Vision as
        // art. On a neutral backdrop with no rim to take off, Vision's cut is
        // kept whole. (On a coloured one the fringe would go: see the twigs.)
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 50 { return self.red }
            return d <= 62 ? (186, 186, 180) : (170, 170, 170)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 62 })
        XCTAssertEqual(report.modelRimWidth, 0)
        XCTAssertGreaterThan(at(out, report, 120 + 56, 120)[3], 200, "the pale fringe is art")
    }

    func testTheModelsDropShadowIsNotSticker() throws {
        // A darker-backdrop shadow under the sticker, which Vision took in.
        let shadow: (Double, Double) -> Bool = { x, y in
            let dx = (x - 120) / 75, dy = (y - 150) / 55
            return dx * dx + dy * dy <= 1
        }
        let raw = picture { x, y in
            self.sticker(x, y) ?? (shadow(x, y) ? (84, 119, 140) : nil)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 || shadow(x, y) })
        XCTAssertEqual(at(out, report, 120, 202)[3], 0, "the shadow below the rim is gone")
        XCTAssertEqual(at(out, report, 120, 120 + 55)[3], 255)
    }

    func testABusyBackdropStillLosesTheRim() throws {
        // Not flat, so not keyable: Vision's cut is the mask, and the rim inside
        // it is still found by its colour.
        var seed: UInt64 = 7
        let raw = picture { x, y in
            if let s = self.sticker(x, y) { return s }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            return (v, 255 - v, v / 2)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertFalse(report.keyed)
        XCTAssertEqual(at(out, report, 120 - 65, 120)[3], 0)
        XCTAssertEqual(at(out, report, 120, 120)[3], 255)
    }

    func testAThinStringOnBareArtStays() throws {
        // Art drawn with no model rim (the swan case): a 5 px dark string hangs
        // below a bare disc. Nothing is removed from bare art.
        let string: (Double, Double) -> Bool = { x, y in abs(x - 120) <= 2 && y > 60 && y < 220 }
        let raw = picture { x, y in
            self.r(x, y) <= 60 ? self.red : (string(x, y) ? self.ink : nil)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 60 || string(x, y) })
        XCTAssertEqual(report.modelRimWidth, 0)
        XCTAssertEqual(at(out, report, 120, 205), [40, 30, 30, 255], "the string is still drawn")
    }

    func testAWhiteBodyBehindTheRimKeepsItsShape() throws {
        // A white body with no outline of its own, touching the model's rim:
        // only a band the rim's width comes off, the body stays.
        let body: (UInt8, UInt8, UInt8) = (244, 244, 244)
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 8 { return self.ink }
            if d <= 60 { return body }
            if d <= 70 { return self.rimWhite }
            return nil
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertGreaterThan(report.whiteBodyPixels, 0)
        XCTAssertEqual(at(out, report, 120 - 40, 120)[3], 255, "the body stays")
        XCTAssertEqual(at(out, report, 120, 120), [40, 30, 30, 255])
        XCTAssertEqual(at(out, report, 120 - 68, 120)[3], 0, "the outer band goes")
    }

    func testWhiteThatRunsFarInsideIsKeptWhole() throws {
        // A white body with no outline (a white rabbit), or art on white paper:
        // the white runs far deeper than any rim, so none of it is taken --
        // a band off it would be a band off the rabbit.
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 8 { return self.ink }
            if d <= 70 { return self.rimWhite }
            return nil
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertEqual(at(out, report, 120 - 40, 120)[3], 255, "the body stays")
        XCTAssertEqual(at(out, report, 120 - 66, 120)[3], 255, "its outer band stays too")
        XCTAssertTrue(report.drawnOnPaper)
        XCTAssertEqual(report.pockets, 0)
    }

    func testAFlatBackingJoiningTwoPartsIsRemoved() throws {
        // The stars: two red discs on one white backing the model drew round
        // both, wider between them than the rim alone would be.
        let left = (60.0, 120.0), right = (180.0, 120.0)
        let raw = picture { x, y in
            if self.r(x, y, left.0, left.1) <= 35 || self.r(x, y, right.0, right.1) <= 35 { return self.red }
            if self.r(x, y, left.0, left.1) <= 45 || self.r(x, y, right.0, right.1) <= 45 { return self.rimWhite }
            if x > left.0, x < right.0, abs(y - 120) <= 45 { return self.rimWhite }
            return nil
        }
        let lifted = alpha { x, y in
            self.r(x, y, left.0, left.1) <= 45 || self.r(x, y, right.0, right.1) <= 45
                || (x > left.0 && x < right.0 && abs(y - 120) <= 45)
        }
        let (out, report) = try run(raw, lifted)
        XCTAssertEqual(at(out, report, 120, 120)[3], 0, "the backing between them is gone")
        XCTAssertEqual(at(out, report, 120, 80)[3], 0)
        XCTAssertEqual(at(out, report, 60, 120)[3], 255)
        XCTAssertEqual(at(out, report, 180, 120)[3], 255)
    }

    func testAPocketClosedByThinLinesIsRemoved() throws {
        // A balloon: two 3 px ropes from the envelope to a basket bar. The
        // model's rim fills the space between them, which the ropes close off.
        let envelope: (Double, Double) -> Bool = { x, y in self.r(x, y, 120, 75) <= 60 }
        let rope: (Double, Double) -> Bool = { x, y in
            (abs(x - 108) <= 1 || abs(x - 132) <= 1) && y > 125 && y < 166
        }
        let bar: (Double, Double) -> Bool = { x, y in x >= 100 && x <= 140 && y >= 163 && y <= 171 }
        let art: (Double, Double) -> Bool = { x, y in envelope(x, y) || rope(x, y) || bar(x, y) }
        var artMask = [Bool](repeating: false, count: size * size)
        for y in 0..<size { for x in 0..<size { artMask[y * size + x] = art(Double(x), Double(y)) } }
        let near = StickerEdge.distance(to: artMask, size, size)
        let raw = picture { x, y in
            if envelope(x, y) { return self.red }
            if rope(x, y) || bar(x, y) { return self.ink }
            return near[Int(y) * self.size + Int(x)] <= 12 ? self.rimWhite : nil
        }
        let lifted = alpha { x, y in near[Int(y) * self.size + Int(x)] <= 12 }
        let (out, report) = try run(raw, lifted)
        XCTAssertEqual(at(out, report, 120, 150)[3], 0, "the pocket between the ropes is gone")
        XCTAssertGreaterThan(at(out, report, 108, 150)[3], 200, "the rope is not")
        XCTAssertGreaterThan(report.pockets, 0)
    }

    func testAnEyesWhiteIsKept() throws {
        // White inside the art, far from the rim: an eye, not a pocket.
        let raw = picture { x, y in
            if self.r(x, y, 100, 105) <= 6 { return self.ink }
            if self.r(x, y, 100, 105) <= 16 { return self.rimWhite }
            if self.r(x, y) <= 60 { return self.ink }
            if self.r(x, y) <= 70 { return self.rimWhite }
            return nil
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 70 })
        XCTAssertEqual(at(out, report, 100 + 11, 105), [253, 253, 253, 255])
    }

    func testUnreadableInputThrows() {
        XCTAssertThrowsError(try StickerEdge.cleanCut(raw: Data("x".utf8), lifted: Data("y".utf8))) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .undecodable)
        }
    }

    func testMismatchedSizesThrow() {
        let small = Bitmap(width: 10, height: 10).png()!
        let raw = picture(sticker).png()!
        XCTAssertThrowsError(try StickerEdge.cleanCut(raw: raw, lifted: small)) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .sizeMismatch)
        }
    }

    func testNothingLiftedThrows() {
        let raw = picture(sticker).png()!
        let empty = Bitmap(width: size, height: size).png()!
        XCTAssertThrowsError(try StickerEdge.cleanCut(raw: raw, lifted: empty)) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .nothingLifted)
        }
    }

    func testACutKeyedAwayEntirelyThrows() {
        // Vision kept a sliver thinner than trustInset, all of it backdrop: the
        // key leaves nothing, and a throw keeps Vision's cut instead of a blank.
        let raw = picture { _, _ in nil }.png()!
        let sliver = alpha { x, y in self.r(x, y) <= 10 }.png()!
        XCTAssertThrowsError(try StickerEdge.cleanCut(raw: raw, lifted: sliver)) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .nothingLifted)
        }
    }

    func testDistanceMatchesTheEuclideanDefinition() {
        // One feature pixel: every distance is the plain Euclidean one.
        var feature = [Bool](repeating: false, count: 15 * 11)
        feature[5 * 15 + 7] = true
        let d = StickerEdge.distance(to: feature, 15, 11)
        for y in 0..<11 { for x in 0..<15 {
            let expected = (Double((x - 7) * (x - 7) + (y - 5) * (y - 5))).squareRoot()
            XCTAssertEqual(Double(d[y * 15 + x]), expected, accuracy: 1e-5)
        } }
    }

    func testNearestFindsTheClosestFeature() {
        var feature = [Bool](repeating: false, count: 20 * 10)
        feature[2 * 20 + 3] = true
        feature[7 * 20 + 16] = true
        let nearest = StickerEdge.nearest(to: feature, 20, 10)
        XCTAssertEqual(nearest[0], Int32(2 * 20 + 3))
        XCTAssertEqual(nearest[9 * 20 + 19], Int32(7 * 20 + 16))
        XCTAssertEqual(nearest[2 * 20 + 3], Int32(2 * 20 + 3))
    }
}

/// A sticker the server generated, lifted by a stand-in for Vision, comes out
/// without the model's edge -- and one StickerEdge cannot read comes out as lifted.
final class StickerEdgeRoutingTests: XCTestCase {
    private struct FixedMatte: ForegroundMatte {
        let output: Data
        func removeBackground(_ image: Data) throws -> Data { output }
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func disc(rim: Bool) -> Bitmap {
        var b = Bitmap(width: 120, height: 120)
        for y in 0..<120 { for x in 0..<120 {
            let d = (Double((x - 60) * (x - 60) + (y - 60) * (y - 60))).squareRoot()
            let i = (y * 120 + x) * 4
            let c: [UInt8] = d <= 30 ? [200, 30, 30] : (d <= 40 && rim ? [253, 253, 253] : [90, 160, 90])
            b.pixels[i] = c[0]; b.pixels[i + 1] = c[1]; b.pixels[i + 2] = c[2]; b.pixels[i + 3] = 255
        } }
        return b
    }

    private func service(raw: Data, lifted: Data) -> LiveImageStudioService {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"images": ["\#(raw.base64EncodedString())"], "count": 1}"#.utf8))
        }
        return LiveImageStudioService(
            baseURL: URL(string: "http://localhost:8002")!,
            client: HTTPClient(session: StubURLProtocol.makeSession()),
            matte: FixedMatte(output: lifted)
        )
    }

    func testGeneratedStickersComeOutWithoutTheModelsEdge() async throws {
        var cut = disc(rim: true)
        for i in 0..<(120 * 120) {
            let x = i % 120, y = i / 120
            let d = (Double((x - 60) * (x - 60) + (y - 60) * (y - 60))).squareRoot()
            cut.pixels[i * 4 + 3] = d <= 40 ? 255 : 0   // Vision kept the art and the rim
        }

        let batch = try await service(raw: disc(rim: true).png()!, lifted: cut.png()!)
            .generateStickers(prompt: "a red dot")

        let out = try XCTUnwrap(Bitmap(data: batch.images[0]))
        XCTAssertLessThanOrEqual(out.width, 66, "cropped to the art (61 px), rim removed")
        XCTAssertTrue(batch.allMatted)
    }

    func testAStickerTheEdgeCannotReadComesOutAsLifted() async throws {
        // A lift of the wrong size: StickerEdge throws, and Vision's cut is kept.
        let lifted = Bitmap(width: 10, height: 10).png()!

        let batch = try await service(raw: disc(rim: true).png()!, lifted: lifted)
            .generateStickers(prompt: "a red dot")

        XCTAssertEqual(batch.images[0], lifted)
        XCTAssertTrue(batch.allMatted)
    }
}

/// The Outline tool's white edge, drawn on the phone round a sticker that is
/// already cut out.
final class StickerOutlineTests: XCTestCase {
    /// `size` x `size`, coloured where `keep` says, clear elsewhere.
    private func cutout(_ size: Int = 300, _ keep: (Double, Double) -> Bool) -> Bitmap {
        var b = Bitmap(width: size, height: size)
        for y in 0..<size { for x in 0..<size where keep(Double(x), Double(y)) {
            let i = (y * size + x) * 4
            b.pixels[i] = 30; b.pixels[i + 1] = 160; b.pixels[i + 2] = 60; b.pixels[i + 3] = 255
        } }
        return b
    }

    private func r(_ x: Double, _ y: Double) -> Double {
        ((x - 150) * (x - 150) + (y - 150) * (y - 150)).squareRoot()
    }

    private func px(_ b: Bitmap, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * b.width + x) * 4
        return Array(b.pixels[i..<(i + 4)])
    }

    func testTheStickerGetsAWhiteEdgeAndIsCroppedToIt() throws {
        let (out, report) = try StickerEdge.outline(cutout { self.r($0, $1) <= 100 }, StickerEdge.Parameters())
        XCTAssertEqual(report.width, 8 + 1, "4% of a 201 px sticker is 8, the floor is 9")
        XCTAssertEqual(report.padding, report.width, accuracy: 1, "no margin beyond the edge")
        XCTAssertEqual(out.width, 201 + 2 * report.padding, "cropped to the sticker and its edge")
        let c = out.height / 2
        XCTAssertEqual(px(out, out.width / 2, c), [30, 160, 60, 255], "the sticker keeps its colours")
        XCTAssertEqual(px(out, out.width / 2 - 100 - report.width / 2, c), [255, 255, 255, 255], "white edge")
        XCTAssertEqual(px(out, 0, 0)[3], 0, "clear outside the round edge")
        XCTAssertGreaterThan(px(out, 0, c)[3], 0, "and the edge reaches the crop")
    }

    func testTheEdgeIsFourPercentOfABigSticker() throws {
        let (_, report) = try StickerEdge.outline(cutout(700) { x, y in
            ((x - 350) * (x - 350) + (y - 350) * (y - 350)).squareRoot() <= 300
        }, StickerEdge.Parameters())
        XCTAssertEqual(report.width, 24, "4% of 601 px")
    }

    func testAHoleGetsOneRingAndStaysEmpty() throws {
        // A donut: ring 40-100, hole of radius 40, wider than two 9 px edges.
        let (out, report) = try StickerEdge.outline(
            cutout { self.r($0, $1) <= 100 && self.r($0, $1) > 40 }, StickerEdge.Parameters())
        let c = out.width / 2
        XCTAssertEqual(px(out, c, c)[3], 0, "the hole's middle stays empty")
        XCTAssertEqual(px(out, c - 40 + report.width / 2, c), [255, 255, 255, 255], "ringed in white")
    }

    /// A disc with a round hole of `diameter`, outlined with a 9 px edge; the
    /// alpha at the hole's middle.
    private func holeMiddleAlpha(diameter: Double) throws -> UInt8 {
        let (out, report) = try StickerEdge.outline(
            cutout { self.r($0, $1) <= 100 && self.r($0, $1) > diameter / 2 }, StickerEdge.Parameters())
        XCTAssertEqual(report.width, 9)
        let c = out.width / 2
        return px(out, c, c)[3]
    }

    func testAHoleJustUnderTwoEdgesFillsAndJustOverStaysOpen() throws {
        // The team's rule: wider than two edges keeps an empty middle.
        XCTAssertEqual(try holeMiddleAlpha(diameter: 16), 255, "16 px < 2 x 9: fills")
        XCTAssertEqual(try holeMiddleAlpha(diameter: 24), 0, "24 px > 2 x 9: stays open")
    }

    func testAFaintPixelBeyondTheEdgeKeepsItsColour() throws {
        // a soft wisp 20 px out from a 9 px edge: drawn as it was, not whitened
        var cut = cutout { self.r($0, $1) <= 100 }
        let i = (150 * 300 + 150 + 100 + 20) * 4
        cut.pixels[i] = 30; cut.pixels[i + 1] = 160; cut.pixels[i + 2] = 60; cut.pixels[i + 3] = 100
        let (out, report) = try StickerEdge.outline(cut, StickerEdge.Parameters())
        let x = 150 + 100 + 20 - (50 - report.padding)
        let wisp = px(out, x, 150 - (50 - report.padding))
        XCTAssertEqual(Array(wisp[0..<3]), [30, 160, 60])
        XCTAssertEqual(wisp[3], 100)
    }

    func testAGapNarrowerThanTwoEdgesFills() throws {
        // Two bars 10 px apart: narrower than two 9 px edges, so it fills white.
        let (out, report) = try StickerEdge.outline(cutout { x, y in
            y > 100 && y < 200 && ((x > 80 && x < 145) || (x >= 155 && x < 220))
        }, StickerEdge.Parameters())
        let gapX = 150 - (80 + 1) + report.padding
        XCTAssertEqual(px(out, gapX, out.height / 2), [255, 255, 255, 255])
    }

    func testAnOutlinedStickerGetsASecondEdge() throws {
        let once = try StickerEdge.outline(cutout { self.r($0, $1) <= 100 }, StickerEdge.Parameters()).0
        let twice = try StickerEdge.outline(once, StickerEdge.Parameters()).0
        XCTAssertGreaterThan(twice.width, once.width, "the edges stack")
    }

    func testAnEmptyCutOutThrows() {
        XCTAssertThrowsError(try StickerEdge.outline(lifted: Bitmap(width: 20, height: 20).png()!)) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .nothingLifted)
        }
    }

    func testTheLiveServiceDrawsItWithoutTheServer() async throws {
        StubURLProtocol.handler = { request in
            XCTFail("a local outline must not call /border")
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.handler = nil }
        let service = LiveImageStudioService(
            baseURL: URL(string: "http://localhost:8002")!,
            client: HTTPClient(session: StubURLProtocol.makeSession()),
            localOutline: true
        )
        let out = try await service.outline(image: cutout { self.r($0, $1) <= 100 }.png()!)
        XCTAssertNotNil(Bitmap(data: out))
    }

    func testAnEmptyStickerSaysSoInsteadOfTryAgain() async throws {
        let service = LiveImageStudioService(baseURL: URL(string: "http://localhost:8002")!, localOutline: true)
        do {
            _ = try await service.outline(image: Bitmap(width: 20, height: 20).png()!)
            XCTFail("an empty sticker cannot be outlined")
        } catch {
            XCTAssertEqual(error as? OutlineError, .nothingVisible)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }
}

/// Runs the real Vision lift plus StickerEdge.cleanCut over a folder of
/// generated stickers and writes the results for the bench's Python metrics.
/// Skipped unless STICKER_EDGE_BENCH_DIR names a folder with a `raw/` inside
/// (on a Simulator, pass it as TEST_RUNNER_STICKER_EDGE_BENCH_DIR).
final class StickerEdgeBenchTests: XCTestCase {
    func testBenchFolder() throws {
        guard let dir = ProcessInfo.processInfo.environment["STICKER_EDGE_BENCH_DIR"] else {
            throw XCTSkip("set STICKER_EDGE_BENCH_DIR to run the sticker edge bench")
        }
        let root = URL(fileURLWithPath: dir)
        let rawDir = root.appendingPathComponent("raw")
        let tag = ProcessInfo.processInfo.environment["STICKER_EDGE_BENCH_TAG"] ?? "swift"
        let outDir = root.appendingPathComponent("out_\(tag)")
        let liftDir = root.appendingPathComponent("vision_\(tag)")
        let fm = FileManager.default
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: liftDir, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
        XCTAssertFalse(files.isEmpty)
        let useLifted = ProcessInfo.processInfo.environment["STICKER_EDGE_BENCH_LIFTED"]
        var rows: [[String: Any]] = []
        for file in files {
            let raw = try Data(contentsOf: file)
            let name = file.lastPathComponent
            let lifted: Data
            let visionStart = Date()
            if let useLifted {
                // Simulator: Vision's foreground request does not run there, so
                // the Mac's lifts are fed in and only StickerEdge is exercised.
                lifted = try Data(contentsOf: URL(fileURLWithPath: useLifted).appendingPathComponent(name))
            } else {
                lifted = try VisionForegroundMatte().removeBackground(raw)
            }
            let visionSeconds = Date().timeIntervalSince(visionStart)
            try lifted.write(to: liftDir.appendingPathComponent(name))
            let edgeStart = Date()
            let (png, report) = try StickerEdge.cleanCutReporting(raw: raw, lifted: lifted)
            let edgeSeconds = Date().timeIntervalSince(edgeStart)
            try png.write(to: outDir.appendingPathComponent(name))
            rows.append(["name": file.deletingPathExtension().lastPathComponent,
                         "crop": [report.cropX, report.cropY],
                         "model_rim_px": report.modelRimWidth, "keyed": report.keyed,
                         "pockets": report.pockets, "white_body_px": report.whiteBodyPixels,
                         "drawn_on_paper": report.drawnOnPaper,
                         "vision_s": visionSeconds, "edge_s": edgeSeconds])
        }
        let json = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: outDir.appendingPathComponent("report.json"))
    }
}

/// Peak memory one StickerEdge call adds, from the process's physical-footprint
/// high-water mark. Run one image per process (the mark only goes up).
/// Skipped unless STICKER_EDGE_MEM_RAW and STICKER_EDGE_MEM_LIFTED are set;
final class StickerEdgeMemoryBenchTests: XCTestCase {
    private func peakFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(max(0, info.ledger_phys_footprint_peak)) : 0
    }

    func testPeak() throws {
        let env = ProcessInfo.processInfo.environment
        guard let rawPath = env["STICKER_EDGE_MEM_RAW"], let liftedPath = env["STICKER_EDGE_MEM_LIFTED"] else {
            throw XCTSkip("set STICKER_EDGE_MEM_RAW / STICKER_EDGE_MEM_LIFTED to measure peak memory")
        }
        let raw = try Data(contentsOf: URL(fileURLWithPath: rawPath))
        let lifted = try Data(contentsOf: URL(fileURLWithPath: liftedPath))
        let before = peakFootprint()
        _ = try StickerEdge.cleanCut(raw: raw, lifted: lifted)
        let after = peakFootprint()
        print(String(format: "[mem] peak added: %.1f MB", Double(after - before) / 1_048_576))
    }
}
