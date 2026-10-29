import CoreML
import ImageIO
import MiraNoteKit
import UIKit
import Vision

/// One story photo decoded for the screen, with where its faces are.
struct StoryPhoto: Identifiable {
    let photo: TriggerMemory.Photo
    let image: UIImage
    let faces: FacePreservingCrop.Faces

    var id: String { photo.id }

    /// Vision's `perform` blocks while it waits on its own queues. Run on
    /// Swift's cooperative pool, a few of those calls at once starve the pool
    /// and never return, so decoding and face detection get a queue of
    /// their own.
    private static let work = DispatchQueue(label: "ai.miranote.trigger.photos", qos: .userInitiated)

    /// Decodes the photos of `memory` one by one in story order, off the
    /// main actor, handing each over as soon as it is ready -- the story can
    /// start on the first while the rest decode. A photo whose file is
    /// missing or unreadable is skipped.
    static func stream(_ memory: TriggerMemory, from source: TriggerMemorySource) -> AsyncStream<StoryPhoto> {
        let ordered = memory.storyPhotos.map { ($0, source.url(for: $0)) }
        return AsyncStream { continuation in
            work.async {
                for (photo, url) in ordered {
                    guard let url, let image = downsample(url, maxPixel: 1800) else { continue }
                    continuation.yield(StoryPhoto(photo: photo, image: image, faces: detectFaces(in: image)))
                }
                continuation.finish()
            }
        }
    }

    /// An upright image no larger than `maxPixel` on its long edge -- the
    /// full-resolution file would cost tens of megabytes per photo.
    static func downsample(_ url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// The union of the faces Vision finds, flipped to a top-left origin.
    private static func detectFaces(in image: UIImage) -> FacePreservingCrop.Faces {
        guard let cgImage = image.cgImage else { return .unknown }
        let request = VNDetectFaceRectanglesRequest()
        #if targetEnvironment(simulator)
        // The simulator has no Neural Engine: the default device fails with
        // "Could not create inference context", so it runs on the CPU.
        if let cpu = MLComputeDevice.allComputeDevices.first(where: {
            if case .cpu = $0 { return true }
            return false
        }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return .unknown
        }
        let boxes = (request.results ?? []).map(\.boundingBox)
        guard let first = boxes.first else { return .none }
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        return .found(CGRect(x: union.minX, y: 1 - union.maxY, width: union.width, height: union.height))
    }
}
