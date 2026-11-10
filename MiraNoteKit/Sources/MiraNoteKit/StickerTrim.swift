import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Crops the transparent margin off a cut-out sticker.
///
/// A matte comes back the size of the whole canvas with the subject somewhere
/// inside it -- both the on-device one (`croppedToInstancesExtent: false`) and
/// the server's. A canvas item keeps its frame across an edit and renders the
/// image with `scaledToFit`, so that margin is counted as part of the picture
/// and the subject draws smaller inside the same box. The result is saved and
/// becomes the input to the next edit, so it compounds.
///
/// Measured, not estimated: a real generated sticker matted by
/// `VisionForegroundMatte` came back 1024x1024 around a 726x724 subject --
/// 156/144/170/128 px of margin, the subject filling 70.9% of the longest
/// side. That is 0.71x a pass; five edits would leave 18% of the original.
///
/// `/border`'s outline pass used to hide this -- it crops to alpha before and
/// after stroking -- so dropping the stroke dropped the crop with it. This is
/// that crop on its own, without the stroke.
public enum StickerTrim {
    /// Crop `image` to the bounding box of its visible pixels, returning PNG
    /// data.
    ///
    /// Best-effort by contract: the input is returned unchanged when it cannot
    /// be decoded, when nothing in it is visible, when it is already tight, or
    /// when the result cannot be re-encoded. A sticker that is merely not
    /// trimmed is worth far more to the caller than a failed edit, and every
    /// caller here is mid-pipeline with the user waiting.
    ///
    /// `alphaFloor` is the alpha a pixel needs to count as visible. It is not
    /// zero on purpose: a generated sticker often carries a wash of nearly
    /// transparent pixels across the full canvas, and treating those as
    /// content puts the bounding box back at the full size and makes this a
    /// no-op. The server's `_crop_to_alpha` uses PIL's `getbbox()`, which is
    /// effectively a floor of 1, and has the same exposure.
    public static func croppedToOpaqueBounds(_ image: Data, alphaFloor: UInt8 = 2) -> Data {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              decoded.width > 0, decoded.height > 0,
              let box = visibleBounds(of: decoded, alphaFloor: alphaFloor) else {
            return image
        }
        // Already tight: re-encoding would cost a copy and change the bytes
        // for nothing.
        guard box != CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height),
              let cropped = decoded.cropping(to: box),
              let png = pngData(from: cropped) else {
            return image
        }
        return png
    }

    /// How a sticker's frame changes when it gains an even margin round what
    /// showed: the new size, and how far the centre moves in the frame's own,
    /// unrotated axes.
    public struct Regrowth: Equatable, Sendable {
        public var size: CGSize
        public var centerShift: CGVector
    }

    /// The frame `grown` needs so the part of `image` that shows keeps its
    /// size and place on the page, when `grown` is that part with an even
    /// margin round it (Outline's edge). A canvas item draws its image
    /// `scaledToFit` into a frame kept across an edit, so in the old frame
    /// the edge would be fitted in by drawing the art smaller: 7-10% a pass,
    /// again on every Outline (#156 review).
    ///
    /// `frame` is the item's size now. The visible part need not sit in the
    /// middle of `image` (a preset keeps a margin), hence the shift. Nil when
    /// either image cannot be read or nothing in `image` shows.
    public static func regrowth(from image: Data, to grown: Data, in frame: CGSize) -> Regrowth? {
        guard let old = decoded(image), let new = decoded(grown),
              let box = visibleBounds(of: old, alphaFloor: 1) else { return nil }
        let width = CGFloat(old.width), height = CGFloat(old.height)
        let scale = min(frame.width / width, frame.height / height)
        guard scale.isFinite, scale > 0 else { return nil }
        return Regrowth(
            size: CGSize(width: CGFloat(new.width) * scale, height: CGFloat(new.height) * scale),
            centerShift: CGVector(dx: (box.midX - width / 2) * scale, dy: (box.midY - height / 2) * scale)
        )
    }

    private static func decoded(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else { return nil }
        return image
    }

    /// The bounding box of pixels at or above `alphaFloor`, in the image's own
    /// pixel space (origin top-left, matching `CGImage.cropping(to:)`). Nil
    /// when the image has no such pixel, or cannot be rasterised.
    private static func visibleBounds(of image: CGImage, alphaFloor: UInt8) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        guard let buffer = calloc(height, bytesPerRow) else { return nil }
        defer { free(buffer) }

        // A known layout, so the alpha byte is always the fourth of four. The
        // decoded image's own layout is deliberately not trusted: a PNG can
        // arrive indexed, grey, 16-bit, or premultiplied in either order.
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixels = buffer.assumingMemoryBound(to: UInt8.self)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width where pixels[row + x * 4 + 3] >= alphaFloor {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
