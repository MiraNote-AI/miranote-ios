import SwiftUI
import XCTest
@testable import MiraNote

/// The star jar's glass follows the theme (#243): on Forest's dark green
/// it reads as clear glass, not milky; the other themes keep the cream
/// glass as drawn.
@MainActor
final class JarGlassTests: XCTestCase {
    func testOnlyForestTintsItsOwnGlass() {
        XCTAssertEqual(Theme(appearance: .system).jarGlass, .cream)
        XCTAssertEqual(Theme(appearance: .sunlitPop).jarGlass, .cream)
        XCTAssertNotEqual(Theme(appearance: .forest).jarGlass, .cream)
    }

    /// How far the empty jar, back glass and front, lifts the screen
    /// behind it: the mean of the glass's middle (clear of its highlights,
    /// jar units -30...30 across and -90...-20 up), less the background,
    /// 0-255 per channel.
    private func lift(of glass: JarArt.Glass, on background: Color) throws -> Double {
        let renderer = ImageRenderer(content: Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            var jar = context
            jar.translateBy(x: 62, y: 170)
            JarArt.back(in: jar, s: 1, glass: glass)
            JarArt.front(in: jar, s: 1, glass: glass)
        }.frame(width: 124, height: 170))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func channels(_ column: Int, _ row: Int) -> [Double] {
            (0..<3).map { Double(bytes[(row * width + column) * 4 + $0]) }
        }
        // The top left corner is beside the neck: the background alone.
        let screen = channels(0, 0)
        var sum = 0.0, count = 0.0
        for row in 80..<150 {
            for column in 32..<92 {
                sum += zip(channels(column, row), screen).map { $0 - $1 }.reduce(0, +) / 3
                count += 1
            }
        }
        return sum / count
    }

    func testForestsGlassReadsAsGlassOnItsGreen() throws {
        let forest = Theme(appearance: .forest)
        let cream = try lift(of: .cream, on: forest.background)
        let tinted = try lift(of: forest.jarGlass, on: forest.background)
        XCTAssertLessThan(tinted, cream / 2, "the cream glass lifts Forest's green by \(cream), Forest's by \(tinted)")
        XCTAssertGreaterThan(tinted, 2, "Forest's glass still shows: \(tinted)")
    }
}
