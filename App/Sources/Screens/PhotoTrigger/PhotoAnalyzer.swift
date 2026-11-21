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
/// The same pass gives the repeat theme's vision (`checkup`): every likely
/// label with its confidence, and the FeaturePrint as floats.
/// The simulator's labels and FeaturePrints are unusable and left out.
struct PhotoAnalyzer: PhotoAnalyzing {
    let photos: TriggerPhotoProviding
    static let thumbnailPixel: CGFloat = 512
    /// A theme photo keeps at most this many labels (decision 3, as the B7
    /// tool's `analyze.swift`),
    static let themeLabelCount = 20
    /// none less confident than this.
    static let themeLabelFloor: Float = 0.1

    /// Vision's `perform` blocks on its own queues; run on the cooperative
    /// pool, a few at once can starve it (the v0 story learned this), so
    /// the synchronous requests get a queue of their own.
    private static let work = DispatchQueue(label: "ai.miranote.trigger.analysis", qos: .userInitiated)
    private static let prints = FeaturePrintCache()

    func analyze(_ id: String) async -> PhotoAnalysis? {
        await checkup(id)?.analysis
    }

    /// One read of the thumbnail for both trigger modes: V1's analysis and
    /// the theme's vision (nil on the simulator, as V1's prints are).
    func checkup(_ id: String) async -> (analysis: PhotoAnalysis, theme: ThemeVision?)? {
        guard let image = await photos.image(for: id, maxPixel: Self.thumbnailPixel, allowNetwork: false),
              let cgImage = image.cgImage else { return nil }
        // The bitmap is stored as shot; Vision needs to know which way is up.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        guard let classic = await Self.classic(cgImage, orientation: orientation, id: id) else { return nil }
        var analysis = classic.analysis
        if #available(iOS 18.0, *), let scores = await Self.aesthetics(cgImage, orientation: orientation) {
            analysis = PhotoAnalysis(id: id, labels: analysis.labels, broad: analysis.broad, faces: analysis.faces,
                                     aesthetics: scores.overall, isUtility: scores.isUtility || analysis.isUtility,
                                     featurePrint: analysis.featurePrint)
        }
        return (analysis, classic.theme)
    }

    /// The labels a theme photo keeps: the best `themeLabelCount` at
    /// `themeLabelFloor` or more, best first -- all of them, not V1's
    /// high-precision few.
    static func themeLabels(_ classified: [(id: String, confidence: Float)]) -> [LabelScore] {
        classified.filter { $0.confidence >= themeLabelFloor }
            .sorted { ($0.confidence, $1.id) > ($1.confidence, $0.id) }
            .prefix(themeLabelCount)
            .map { LabelScore(id: $0.id, confidence: $0.confidence) }
    }

    /// A FeaturePrint's `count` elements as floats, as Vision stored them
    /// (Float32 or Float64, native byte order); nil for another element
    /// type or data too short. Not scaled: the theme store makes it unit
    /// length (`ThemePhoto.normalized`).
    static func printFloats(_ data: Data, elementType: VNElementType, count: Int) -> [Float]? {
        switch elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return nil }
            return data.withUnsafeBytes { raw in
                (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
            }
        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return nil }
            return data.withUnsafeBytes { raw in
                (0..<count).map {
                    Float(raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Double>.size, as: Double.self))
                }
            }
        default:
            return nil
        }
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

    /// FeaturePrint, labels and faces in one pass: V1's analysis, and the
    /// theme's vision from the same results.
    private static func classic(_ image: CGImage, orientation: CGImagePropertyOrientation,
                                id: String) async -> (analysis: PhotoAnalysis, theme: ThemeVision?)? {
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
                // categories. Faces are fine. Devices are unaffected. The
                // theme's vision is left out the same way (no theme record).
                let labels: [String] = []
                let archived: Data? = nil
                let theme: ThemeVision? = nil
                #else
                let classified = classify.results ?? []
                let labels = classified
                    .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
                    .map(\.identifier)
                let observation = featurePrint.results?.first
                let archived = observation.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }
                let theme = observation.flatMap { print in
                    printFloats(print.data, elementType: print.elementType, count: print.elementCount).map {
                        ThemeVision(labels: themeLabels(classified.map { ($0.identifier, $0.confidence) }),
                                    print: $0, printRevision: featurePrint.revision)
                    }
                }
                #endif
                let broad = BroadCategory.from(labels: labels)
                let analysis = PhotoAnalysis(
                    id: id, labels: labels, broad: broad, faces: faces.results?.count ?? 0, aesthetics: nil,
                    isUtility: broad.contains(.document), featurePrint: archived
                )
                continuation.resume(returning: (analysis, theme))
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
