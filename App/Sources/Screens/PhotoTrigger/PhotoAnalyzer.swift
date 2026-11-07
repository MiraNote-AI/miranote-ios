import CoreML
import MiraNoteKit
import UIKit
import Vision

/// On-device Vision for one library photo (handoff 7.1), from a local
/// ~512 px thumbnail -- never the original, never the network:
/// FeaturePrint (duplicates, MMR), high-precision scene labels mapped to
/// the 15 broad categories, faces, and on iOS 18+ Apple's aesthetics score
/// and utility flag. Before iOS 18, or when the score cannot be computed
/// (the simulator), aesthetics is nil and a `document` label marks utility.
/// The simulator's labels and FeaturePrints are unusable and left out.
struct PhotoAnalyzer: PhotoAnalyzing {
    let photos: TriggerPhotoProviding
    static let thumbnailPixel: CGFloat = 512

    /// Vision's `perform` blocks on its own queues; run on the cooperative
    /// pool, a few at once can starve it (the v0 story learned this), so
    /// the synchronous requests get a queue of their own.
    private static let work = DispatchQueue(label: "ai.miranote.trigger.analysis", qos: .userInitiated)
    private static let prints = FeaturePrintCache()

    func analyze(_ id: String) async -> PhotoAnalysis? {
        guard let image = await photos.image(for: id, maxPixel: Self.thumbnailPixel, allowNetwork: false),
              let cgImage = image.cgImage else { return nil }
        // The bitmap is stored as shot; Vision needs to know which way is up.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        guard var analysis = await Self.classic(cgImage, orientation: orientation, id: id) else { return nil }
        if #available(iOS 18.0, *), let scores = await Self.aesthetics(cgImage, orientation: orientation) {
            analysis = PhotoAnalysis(id: id, labels: analysis.labels, broad: analysis.broad, faces: analysis.faces,
                                     aesthetics: scores.overall, isUtility: scores.isUtility || analysis.isUtility,
                                     featurePrint: analysis.featurePrint)
        }
        return analysis
    }

    func distance(_ first: (id: String, print: Data), _ second: (id: String, print: Data)) -> Float? {
        guard let one = Self.prints.observation(first.id, first.print),
              let two = Self.prints.observation(second.id, second.print) else { return nil }
        var distance: Float = 0
        do {
            try one.computeDistance(&distance, to: two)
        } catch {
            return nil
        }
        return distance
    }

    /// FeaturePrint, labels and faces in one pass.
    private static func classic(_ image: CGImage, orientation: CGImagePropertyOrientation,
                                id: String) async -> PhotoAnalysis? {
        await withCheckedContinuation { continuation in
            work.async {
                let featurePrint = VNGenerateImageFeaturePrintRequest()
                let classify = VNClassifyImageRequest()
                let faces = VNDetectFaceRectanglesRequest()
                let requests: [VNRequest] = [featurePrint, classify, faces]
                #if targetEnvironment(simulator)
                // No Neural Engine: "Could not create inference context".
                requests.forEach(useCPU)
                #endif
                do {
                    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform(requests)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                #if targetEnvironment(simulator)
                // On the simulator's CPU path the classifier answers
                // "outdoor, sky" and the FeaturePrints are all alike for
                // every photo (checked 2026-11-01, iOS 26.5): unusable, so
                // treated as missing -- no fake duplicates, no fake
                // categories. Faces are fine. Devices are unaffected.
                let labels: [String] = []
                let archived: Data? = nil
                #else
                let labels = (classify.results ?? [])
                    .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
                    .map(\.identifier)
                let archived = featurePrint.results?.first.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }
                #endif
                let broad = BroadCategory.from(labels: labels)
                continuation.resume(returning: PhotoAnalysis(
                    id: id, labels: labels, broad: broad, faces: faces.results?.count ?? 0, aesthetics: nil,
                    isUtility: broad.contains(.document), featurePrint: archived
                ))
            }
        }
    }

    @available(iOS 18.0, *)
    private static func aesthetics(_ image: CGImage, orientation: CGImagePropertyOrientation) async
        -> (overall: Double, isUtility: Bool)? {
        #if targetEnvironment(simulator)
        // The simulator cannot run the model: treated as iOS 17 (handoff 7.1).
        return nil
        #else
        guard let observation = try? await CalculateImageAestheticsScoresRequest()
            .perform(on: image, orientation: orientation) else {
            return nil
        }
        return (Double(observation.overallScore), observation.isUtility)
        #endif
    }

    #if targetEnvironment(simulator)
    private static func useCPU(_ request: VNRequest) {
        guard let cpu = MLComputeDevice.allComputeDevices.first(where: {
            if case .cpu = $0 { return true }
            return false
        }) else { return }
        let stages = (try? request.supportedComputeStageDevices).map { Array($0.keys) } ?? [.main]
        for stage in stages {
            request.setComputeDevice(cpu, for: stage)
        }
    }
    #endif
}

/// Unarchived FeaturePrints by photo id, kept while the app runs: grouping
/// and preselection compare the same photos many times. (Keyed by id, not
/// by the bytes: hashing kilobytes of data per lookup cost more than it saved.)
private final class FeaturePrintCache: @unchecked Sendable {
    private let cache = NSCache<NSString, VNFeaturePrintObservation>()

    func observation(_ id: String, _ data: Data) -> VNFeaturePrintObservation? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let observation = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self,
                                                                         from: data) else { return nil }
        cache.setObject(observation, forKey: id as NSString)
        return observation
    }
}

extension CGImagePropertyOrientation {
    /// The EXIF orientation of a UIKit one (their raw values differ).
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
