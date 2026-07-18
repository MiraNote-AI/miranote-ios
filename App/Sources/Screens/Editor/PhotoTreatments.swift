import CoreImage
import CoreImage.CIFilterBuiltins
import MiraNoteKit
import SwiftUI
import UIKit

/// The curated filter strip (v2.1: instant presets, never per-use AI).
/// `match` is the page-aware slot: tones shift toward the warm paper.
enum PhotoFilter: String, CaseIterable, Identifiable {
    case match, none, bw, warm, film

    var id: String { rawValue }

    var label: String {
        switch self {
        case .match: return "Match page"
        case .none: return "Original"
        case .bw: return "B&W"
        case .warm: return "Warm"
        case .film: return "Film"
        }
    }

    /// Applies the preset; `none` returns the input untouched.
    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image
        case .bw:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = image
            return filter.outputImage ?? image
        case .warm:
            // CITemperatureAndTint runs toward LOWER Kelvin for warmth: a
            // target above neutral cools (measured: 5200->7200 tints grey
            // blue). Warm therefore aims the target BELOW the neutral.
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 5200, y: 10)
            return filter.outputImage ?? image
        case .film:
            let filter = CIFilter.photoEffectInstant()
            filter.inputImage = image
            return filter.outputImage ?? image
        case .match:
            // Harmonize with the warm paper: gentle warmth + a touch less
            // saturation so photos sit into the page instead of on it.
            let warmth = CIFilter.temperatureAndTint()
            warmth.inputImage = image
            warmth.neutral = CIVector(x: 6500, y: 0)
            warmth.targetNeutral = CIVector(x: 5800, y: 5)
            let soften = CIFilter.colorControls()
            soften.inputImage = warmth.outputImage ?? image
            soften.saturation = 0.86
            soften.brightness = 0.02
            soften.contrast = 1.0
            return soften.outputImage ?? image
        }
    }
}

/// Scrapbook photo edges (v2.1 "Frame"): none / thin white / polaroid.
enum PhotoFrame: String, CaseIterable, Identifiable {
    case none, white, polaroid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .white: return "White"
        case .polaroid: return "Polaroid"
        }
    }
}

/// Loads, filters, and caches canvas images so scrolling stays smooth.
enum CanvasImageCache {
    private static let cache = NSCache<NSString, UIImage>()
    private static let context = CIContext()

    static func image(fileName: String, filterName: String, store: ImageFileStore) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        let key = "\(fileName)|\(filterName)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let data = store.data(forFileName: fileName),
              let base = UIImage(data: data) else {
            return nil
        }
        let filter = PhotoFilter(rawValue: filterName) ?? .none
        let result: UIImage
        if filter == .none {
            result = base
        } else if let input = CIImage(image: base) {
            let output = filter.apply(to: input)
            if let cg = context.createCGImage(output, from: output.extent) {
                result = UIImage(cgImage: cg, scale: base.scale, orientation: base.imageOrientation)
            } else {
                result = base
            }
        } else {
            result = base
        }
        cache.setObject(result, forKey: key)
        return result
    }
}

extension UIImage {
    /// Picked photos are stored at a sane size for a phone canvas.
    func downscaled(maxDimension: CGFloat = 1440) -> Data? {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else {
            return jpegData(compressionQuality: 0.85) ?? pngData()
        }
        let scaleFactor = maxDimension / largest
        let target = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        // Render at scale 1: the renderer's default format multiplies by
        // the SCREEN scale (3x on Pro phones), silently storing a 4320px
        // image where 1440 was intended -- 9x the pixels, and minutes of
        // extra /cutout time per sticker.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85) ?? resized.pngData()
    }
}
