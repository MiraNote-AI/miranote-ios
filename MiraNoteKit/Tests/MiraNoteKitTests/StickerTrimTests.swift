import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MiraNoteKit

/// `StickerTrim` crops the transparent margin off a matte. The margin is why
/// an edited sticker used to shrink: the canvas item keeps its frame and fits
/// the whole image into it, so transparent padding is drawn as picture.
final class StickerTrimTests: XCTestCase {
    func testCropsTheMarginDownToTheSubject() throws {
        // Subject 10 wide, 20 tall, parked off-centre in a 100x100 canvas.
        let data = try png(canvas: 100, subject: (x: 40, y: 30, width: 10, height: 20))
        let trimmed = StickerTrim.croppedToOpaqueBounds(data)
        let size = try sizeOf(trimmed)
        XCTAssertEqual(size.width, 10, "width collapses to the subject")
        XCTAssertEqual(size.height, 20, "height collapses to the subject")
    }

    /// The crop has to land on the subject, not on the margin opposite it.
    ///
    /// `visibleBounds` scans a bitmap context's buffer while `cropping(to:)`
    /// addresses the image, so a disagreement about which end of the buffer is
    /// the top of the image would mirror the box vertically and still produce
    /// exactly the right size. Here the subject hugs the top edge and all the
    /// margin is below it, so a mirrored box would crop an entirely
    /// transparent region -- caught by counting visible pixels, which does not
    /// itself depend on the orientation being right.
    func testCropLandsOnTheSubjectAndNotTheOppositeMargin() throws {
        let data = try png(canvas: 100, subject: (x: 0, y: 0, width: 10, height: 20))
        let trimmed = StickerTrim.croppedToOpaqueBounds(data)
        let size = try sizeOf(trimmed)
        XCTAssertEqual(size.width, 10)
        XCTAssertEqual(size.height, 20)
        XCTAssertEqual(try visiblePixelCount(in: trimmed), 200,
                       "every pixel of the kept box is the subject, so the box "
                       + "is the subject and not the margin facing it")
    }

    func testAnAlreadyTightImageComesBackUntouched() throws {
        let data = try png(canvas: 20, subject: (x: 0, y: 0, width: 20, height: 20))
        XCTAssertEqual(StickerTrim.croppedToOpaqueBounds(data), data,
                       "nothing to crop, so not even a re-encode")
    }

    func testTrimmingTwiceChangesNothingTheSecondTime() throws {
        let once = StickerTrim.croppedToOpaqueBounds(
            try png(canvas: 100, subject: (x: 12, y: 34, width: 30, height: 40)))
        XCTAssertEqual(StickerTrim.croppedToOpaqueBounds(once), once,
                       "idempotent -- an edited sticker is trimmed again on "
                       + "every later edit and must stop shrinking")
    }

    func testAFullyTransparentImageComesBackUntouched() throws {
        let data = try png(canvas: 20, subject: nil)
        XCTAssertEqual(StickerTrim.croppedToOpaqueBounds(data), data,
                       "no visible pixel to crop to")
    }

    func testBytesThatAreNotAnImageComeBackUntouched() {
        let data = Data("not a png".utf8)
        XCTAssertEqual(StickerTrim.croppedToOpaqueBounds(data), data,
                       "fail open: a sticker that is merely untrimmed beats a "
                       + "failed edit, and the fakes in the turn tests are "
                       + "plain strings")
    }

    func testAFaintWashAcrossTheCanvasDoesNotDefeatTheCrop() throws {
        // What a generated sticker actually looks like: alpha 1 everywhere,
        // solid subject in the middle.
        let data = try png(canvas: 100, subject: (x: 40, y: 40, width: 10, height: 10), wash: 1)
        let size = try sizeOf(StickerTrim.croppedToOpaqueBounds(data))
        XCTAssertEqual(size.width, 10, "alpha 1 is not content")
        XCTAssertEqual(size.height, 10)
    }

    func testAtFloorZeroTheWashCountsAndNothingIsCropped() throws {
        let data = try png(canvas: 100, subject: (x: 40, y: 40, width: 10, height: 10), wash: 1)
        XCTAssertEqual(StickerTrim.croppedToOpaqueBounds(data, alphaFloor: 0), data,
                       "the floor is what separates a wash from a subject")
    }
}

// MARK: - fixtures

extension StickerTrimTests {
    private struct CouldNotBuildFixture: Error {}

    /// A square RGBA PNG: `wash` alpha everywhere, an opaque white `subject`
    /// on top of it. Built from raw rows rather than by drawing, so the first
    /// row is the top of the image by construction.
    private func png(
        canvas: Int,
        subject: (x: Int, y: Int, width: Int, height: Int)?,
        wash: UInt8 = 0
    ) throws -> Data {
        let bytesPerRow = canvas * 4
        var pixels = [UInt8](repeating: 0, count: canvas * bytesPerRow)
        for y in 0..<canvas {
            for x in 0..<canvas {
                let offset = y * bytesPerRow + x * 4
                let inside = subject.map {
                    x >= $0.x && x < $0.x + $0.width && y >= $0.y && y < $0.y + $0.height
                } ?? false
                let alpha: UInt8 = inside ? 255 : wash
                pixels[offset] = alpha       // premultiplied white
                pixels[offset + 1] = alpha
                pixels[offset + 2] = alpha
                pixels[offset + 3] = alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: canvas,
                  height: canvas,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw CouldNotBuildFixture()
        }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw CouldNotBuildFixture()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CouldNotBuildFixture() }
        return out as Data
    }

    private func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CouldNotBuildFixture()
        }
        return image
    }

    private func sizeOf(_ data: Data) throws -> (width: Int, height: Int) {
        let image = try decode(data)
        return (image.width, image.height)
    }

    /// How many pixels are visible at all. A count, so it says nothing about
    /// where they are and cannot inherit an orientation mistake.
    private func visiblePixelCount(in data: Data, alphaFloor: UInt8 = 2) throws -> Int {
        let image = try decode(data)
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        try pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw CouldNotBuildFixture()
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 3, to: pixels.count, by: 4).count { pixels[$0] >= alphaFloor }
    }
}
