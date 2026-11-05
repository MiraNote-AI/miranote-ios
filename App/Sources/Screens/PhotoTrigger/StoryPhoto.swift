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

    /// The longest one photo may take to arrive (an iCloud download that
    /// stalls): past it the photo is skipped.
    static let timeLimit: TimeInterval = 10

    /// Loads the photos of `memory` one by one in story order (the peak
    /// first) from the library by their localIdentifiers (`photoIds`),
    /// handing each over as soon as it is ready -- the story can start
    /// while the rest load. A photo that cannot be read, or does not
    /// arrive `within` seconds, is skipped.
    static func stream(_ memory: TriggerMemory, photoIds: [String: String], from photos: TriggerPhotoProviding,
                       within limit: TimeInterval = timeLimit) -> AsyncStream<StoryPhoto> {
        let ordered = memory.storyPhotos
        return AsyncStream { continuation in
            let task = Task {
                for photo in ordered {
                    guard let id = photoIds[photo.id],
                          let image = await TimeLimit.first(within: limit, {
                              await photos.image(for: id, maxPixel: 1800, allowNetwork: true)
                          })
                    else { continue }
                    let faces = await withCheckedContinuation { done in
                        work.async { done.resume(returning: detectFaces(in: image)) }
                    }
                    continuation.yield(StoryPhoto(photo: photo, image: image, faces: faces))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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

/// When a story starts, and when it gives up (handoff 7.6, D4): it plays
/// once three photos are ready -- the fewest a story has -- and, every
/// photo tried, with fewer it closes quietly to Home.
enum StoryStart: Equatable {
    case wait, play, leave

    static let fewest = 3

    static func decide(ready: Int, allTried: Bool) -> StoryStart {
        if ready >= fewest { return .play }
        return allTried ? .leave : .wait
    }
}
