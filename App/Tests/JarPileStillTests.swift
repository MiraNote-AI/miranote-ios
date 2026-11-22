import SwiftUI
import XCTest
@testable import MiraNote

/// The Save fold draws the jar's pile from one still image, with only the
/// stars the landing pushes drawn live (#234 review): it must look like
/// the pile drawn star by star.
@MainActor
final class JarPileStillTests: XCTestCase {
    /// The jar's frame rendered as the still is (a point a jar unit, at the
    /// screen's scale), as RGBA bytes.
    private func pixels(_ draw: @escaping (GraphicsContext) -> Void) throws -> [UInt8] {
        let frame = JarPile.frame
        let renderer = ImageRenderer(content: Canvas { context, _ in
            var jar = context
            jar.translateBy(x: -frame.minX, y: -frame.minY)
            draw(jar)
        }.frame(width: frame.width, height: frame.height))
        renderer.scale = UITraitCollection.current.displayScale
        let image = try XCTUnwrap(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    func testTheStillAndTheLiveStarsLookLikeThePileDrawnStarByStar() throws {
        let pile = JarPile((0..<36).map { _ in UUID() })
        let landing = try XCTUnwrap(pile.stars.dropFirst(20).first)
        let nudged: (JarPile.Star) -> Bool = {
            hypot($0.center.x - landing.center.x, $0.center.y - landing.center.y) < 30
        }
        let still = try XCTUnwrap(pile.still(except: landing.id) { !nudged($0) })
        XCTAssertGreaterThan(pile.stars.filter(nudged).count, 1, "some stars stay live")
        XCTAssertLessThan(pile.stars.filter(nudged).count, 36, "and most are in the still")

        let starByStar = try pixels { pile.draw(in: $0, except: landing.id) }
        let fromStill = try pixels { jar in
            jar.draw(still, in: JarPile.frame)
            pile.draw(in: jar, except: landing.id, where: nudged)
        }
        let drawn = starByStar.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count
        XCTAssertGreaterThan(drawn, starByStar.count / 4 / 10, "the pile covers part of the jar")
        let difference = zip(starByStar, fromStill).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        let mean = Double(difference) / Double(starByStar.count)
        XCTAssertLessThan(mean, 1.5, "mean byte difference \(mean)")
    }
}
