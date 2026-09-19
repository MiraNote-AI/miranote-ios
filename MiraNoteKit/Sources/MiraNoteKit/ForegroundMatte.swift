import CoreImage
import Foundation
import Vision

/// Background removal that runs where the photo already is.
///
/// The image service does this too, on the team's Mac, by keeping a Swift
/// subprocess alive next to a Python server and talking to it over a pipe --
/// all of which exists only because Python cannot call Vision. The app is
/// Swift, so here it is one function call, and the photo never leaves the
/// device.
///
/// A protocol rather than a free function so tests can supply a matte that
/// fails on demand: the interesting behaviour in the callers is what they do
/// when there is nothing to lift.
public protocol ForegroundMatte: Sendable {
    /// Lift the salient foreground out of `image`, returning RGBA PNG data.
    func removeBackground(_ image: Data) throws -> Data
}

public enum ForegroundMatteError: Error, Equatable {
    /// Vision found no salient foreground. Ordinary for a landscape, a flat
    /// backdrop, or an image that has already been cut out -- not a defect,
    /// and the reason callers show the picture rather than an error.
    case noSubject
    /// The bytes were not an image this device can read.
    case undecodable
    /// Vision produced a mask that could not be encoded.
    case unencodable
}

/// `VNGenerateForegroundInstanceMaskRequest`, which is what the Photos app
/// uses when you press and hold a subject to lift it out.
///
/// Deliberately the older Vision request class. The Swift-native form
/// (`ImageRequestHandler` / `GenerateForegroundInstanceMaskRequest`) that the
/// server's helper uses needs iOS 18, and adopting it here would raise the
/// app's floor from iOS 17 for no gain -- the two produce the same mask.
public struct VisionForegroundMatte: ForegroundMatte {
    public init() {}

    public func removeBackground(_ image: Data) throws -> Data {
        // Built per call. CIContext is documented as expensive to create, but
        // a matte happens once per user action, and a shared one would need
        // its own synchronisation to stay Sendable. Hoist it if a profile ever
        // says this shows up.
        let context = CIContext()

        // applyOrientationProperty, so a photo carrying EXIF rotation is
        // analysed the way it is displayed. Without it the mask comes back
        // rotated against the source, which is the same trap the server's
        // helper documents around 5.jpeg in its bench set.
        guard let input = CIImage(data: image, options: [.applyOrientationProperty: true]),
              let cgImage = context.createCGImage(input, from: input.extent) else {
            throw ForegroundMatteError.undecodable
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw ForegroundMatteError.noSubject
        }

        // Every instance, not a chosen one: this stands in for whole-foreground
        // removal, the same union the server's helper takes.
        let masked = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        guard let png = context.pngRepresentation(
            of: CIImage(cvPixelBuffer: masked),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            throw ForegroundMatteError.unencodable
        }
        return png
    }
}
