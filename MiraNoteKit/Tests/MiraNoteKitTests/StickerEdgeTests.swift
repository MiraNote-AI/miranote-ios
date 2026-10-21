import XCTest
@testable import MiraNoteKit

/// StickerEdge on drawn inputs whose right answer is known by construction:
/// a red disc with a white rim on a flat backdrop, and a "Vision" alpha that
/// gets it wrong in the ways the bench saw Vision get it wrong.
final class StickerEdgeTests: XCTestCase {
    private let size = 240
    private let backdrop: (UInt8, UInt8, UInt8) = (120, 170, 200)
    private let center = (120.0, 120.0)

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

    private func r(_ x: Double, _ y: Double) -> Double {
        ((x - center.0) * (x - center.0) + (y - center.1) * (y - center.1)).squareRoot()
    }

    /// A red disc of radius 60 inside a white model rim out to 80.
    private func sticker(_ x: Double, _ y: Double) -> (UInt8, UInt8, UInt8)? {
        let d = r(x, y)
        if d <= 60 { return (210, 40, 40) }
        if d <= 80 { return (253, 253, 253) }
        return nil
    }

    private func run(_ raw: Bitmap, _ lifted: Bitmap) throws -> (Bitmap, StickerEdge.Report) {
        let out = try StickerEdge.rebuildReporting(raw: raw.png()!, lifted: lifted.png()!)
        return (Bitmap(data: out.png)!, out.report)
    }

    /// Pixel of `out` at raw coordinates (x, y).
    private func at(_ out: Bitmap, _ report: StickerEdge.Report, _ x: Int, _ y: Int) -> [UInt8] {
        let i = ((y + report.padding) * out.width + x + report.padding) * 4
        return Array(out.pixels[i..<(i + 4)])
    }

    func testARimVisionDroppedComesBackWhite() throws {
        // Vision keeps the disc but loses the rim on the whole left half.
        let lifted = alpha { x, y in self.r(x, y) <= 60 || (self.r(x, y) <= 80 && x > 120) }

        let (out, report) = try run(picture(sticker), lifted)

        XCTAssertTrue(report.keyed)
        XCTAssertGreaterThan(report.modelRimWidth, 0, "the model's rim is recognised")
        let leftRim = at(out, report, 120 - 70, 120)
        XCTAssertEqual(leftRim[3], 255, "the dropped rim is opaque again")
        XCTAssertTrue(leftRim[0..<3].allSatisfy { $0 >= 250 }, "and white: \(leftRim)")
        let beyond = at(out, report, 120 - 80 - report.rimWidth - 8, 120)
        XCTAssertEqual(beyond[3], 0, "and the sticker ends a rim's width further out")
    }

    func testTheArtKeepsItsColours() throws {
        let (out, report) = try run(picture(sticker), alpha { x, y in self.r(x, y) <= 80 })
        XCTAssertEqual(at(out, report, 120, 120), [210, 40, 40, 255])
    }

    func testTheOutputIsPaddedForTheRim() throws {
        let (out, report) = try run(picture(sticker), alpha { x, y in self.r(x, y) <= 80 })
        XCTAssertEqual(out.width, size + 2 * report.padding)
        XCTAssertGreaterThan(report.padding, report.rimWidth)
    }

    func testAHoleRingedByWhiteStaysAHole() throws {
        // A mug handle: backdrop showing through, the model's rim all round it.
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 14 { return nil }
            if d <= 26 { return (253, 253, 253) }
            return self.sticker(x, y)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) > 14 && self.r(x, y) <= 80 })
        XCTAssertEqual(at(out, report, 120, 120)[3], 0)
    }

    func testABackdropColouredFillInsideAnOutlineIsBody() throws {
        // The blue star: filled with the backdrop's own colour, ringed by its
        // drawn outline rather than white, and missed by Vision.
        let raw = picture { x, y in
            let d = self.r(x, y)
            if d <= 30 { return nil }
            if d <= 36 { return (40, 60, 140) }
            return self.sticker(x, y)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) > 30 && self.r(x, y) <= 80 })
        XCTAssertEqual(at(out, report, 120, 120)[3], 255, "the fill is not punched out")
    }

    func testTheModelsDropShadowIsNotSticker() throws {
        // A darker-backdrop shadow under the sticker, which Vision took in.
        let shadow: (Double, Double) -> Bool = { x, y in
            let dx = (x - 120) / 85, dy = (y - 160) / 60
            return dx * dx + dy * dy <= 1
        }
        let raw = picture { x, y in
            self.sticker(x, y) ?? (shadow(x, y) ? (84, 119, 140) : nil)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 80 || shadow(x, y) })
        let deepInShadow = at(out, report, 120, 218)
        XCTAssertEqual(deepInShadow[3], 0, "the shadow below the rim is gone")
    }

    func testABusyBackdropFallsBackToVisionsCut() throws {
        // Not flat, so not keyable: the rim is drawn round what Vision kept.
        var seed: UInt64 = 7
        let raw = picture { x, y in
            if let s = self.sticker(x, y) { return s }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            return (v, 255 - v, v / 2)
        }
        let (out, report) = try run(raw, alpha { x, y in self.r(x, y) <= 80 })
        XCTAssertFalse(report.keyed)
        XCTAssertEqual(at(out, report, 120 - 85, 120)[3], 255, "the rim still goes round it")
    }

    func testUnreadableInputThrows() {
        XCTAssertThrowsError(try StickerEdge.rebuild(raw: Data("x".utf8), lifted: Data("y".utf8))) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .undecodable)
        }
    }

    func testMismatchedSizesThrow() {
        let small = Bitmap(width: 10, height: 10).png()!
        let raw = picture(sticker).png()!
        XCTAssertThrowsError(try StickerEdge.rebuild(raw: raw, lifted: small)) {
            XCTAssertEqual($0 as? StickerEdge.Failure, .sizeMismatch)
        }
    }

    func testNothingLiftedThrows() {
        let raw = picture(sticker).png()!
        let empty = Bitmap(width: size, height: size).png()!
        XCTAssertThrowsError(try StickerEdge.rebuild(raw: raw, lifted: empty)) {
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
            XCTAssertEqual(d[y * 15 + x], expected, accuracy: 1e-9)
        } }
    }
}

/// A sticker the server generated, lifted by a stand-in for Vision, comes out
/// with its edge redrawn -- and one the redraw cannot read comes out as lifted.
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

    func testGeneratedStickersGetTheirEdgeRedrawn() async throws {
        let raw = disc(rim: true).png()!
        var cut = disc(rim: true)
        for i in 0..<(120 * 120) {
            let x = i % 120, y = i / 120
            let d = (Double((x - 60) * (x - 60) + (y - 60) * (y - 60))).squareRoot()
            cut.pixels[i * 4 + 3] = d <= 30 ? 255 : 0   // Vision kept the art, lost the rim
        }
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"images": ["\#(raw.base64EncodedString())"], "count": 1}"#.utf8))
        }
        let service = LiveImageStudioService(
            baseURL: URL(string: "http://localhost:8002")!,
            client: HTTPClient(session: StubURLProtocol.makeSession()),
            matte: FixedMatte(output: cut.png()!)
        )

        let batch = try await service.generateStickers(prompt: "a red dot")

        let out = try XCTUnwrap(Bitmap(data: batch.images[0]))
        XCTAssertGreaterThan(out.width, 120, "padded for the redrawn rim")
        XCTAssertTrue(batch.allMatted)
    }
}

/// Runs the real Vision lift plus StickerEdge over a folder of generated
/// stickers and writes the results for the bench's Python metrics. Skipped
/// unless STICKER_EDGE_BENCH_DIR names a folder with a `raw/` inside
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
                // Simulator: Vision's foreground request may not run there, so
                // the Mac's lifts are fed in and only StickerEdge is exercised.
                lifted = try Data(contentsOf: URL(fileURLWithPath: useLifted).appendingPathComponent(name))
            } else {
                lifted = try VisionForegroundMatte().removeBackground(raw)
            }
            let visionSeconds = Date().timeIntervalSince(visionStart)
            try lifted.write(to: liftDir.appendingPathComponent(name))
            let edgeStart = Date()
            let (png, report) = try StickerEdge.rebuildReporting(raw: raw, lifted: lifted)
            let edgeSeconds = Date().timeIntervalSince(edgeStart)
            try png.write(to: outDir.appendingPathComponent(name))
            rows.append(["name": file.deletingPathExtension().lastPathComponent,
                         "pad": report.padding, "rim_px": report.rimWidth,
                         "model_rim_px": report.modelRimWidth, "keyed": report.keyed,
                         "vision_s": visionSeconds, "edge_s": edgeSeconds])
        }
        let json = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: outDir.appendingPathComponent("report.json"))
    }
}
