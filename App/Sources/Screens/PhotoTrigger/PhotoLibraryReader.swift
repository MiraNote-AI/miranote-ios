import MiraNoteKit
import Photos
import UIKit

/// Library photos by localIdentifier, for the story, the push cover, the
/// canvas draft and the "is it still there" check.
protocol TriggerPhotoProviding: Sendable {
    /// An upright image no larger than `maxPixel` on its long side.
    func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage?
    /// Which of `ids` are still in the library (an edited photo keeps its id).
    func existing(_ ids: [String]) async -> Set<String>
}

/// PhotoKit for the photo trigger (handoff 7.1): metadata of image assets
/// (never videos), small local thumbnails for Vision, larger images for
/// upload and the story. Authorization works like the Recents grid's
/// (`RecentPhotos`): asked once, limited access uses what it can see.
struct PhotoLibraryReader: PhotoLibraryReading, TriggerPhotoProviding {
    /// Original file names are read for this window only (filtering and
    /// the threshold need them); older photos are used for their position.
    static let filenameDays: Double = 91

    func requestAccess() async -> PhotoAccess {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        default: return .denied
        }
    }

    func assets(since date: Date, knownFilenames: [String: String]) async -> [LibraryAsset] {
        await Task.detached(priority: .userInitiated) {
            Self.fetch(since: date, known: knownFilenames)
        }.value
    }

    private static func fetch(since date: Date, known: [String: String]) -> [LibraryAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", date as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // Hidden photos are not fetched by default; screenshots are marked.
        let result = PHAsset.fetchAssets(with: .image, options: options)
        let filenameStart = Date().addingTimeInterval(-filenameDays * 86_400)
        var assets: [LibraryAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            let recent = (asset.creationDate ?? .distantPast) >= filenameStart
            // Names kept from earlier analyses spare a PhotoKit call per photo.
            let name = known[asset.localIdentifier]
                ?? (recent ? PHAssetResource.assetResources(for: asset).first?.originalFilename : nil)
            assets.append(LibraryAsset(
                id: asset.localIdentifier,
                takenAt: asset.creationDate,
                location: asset.location.flatMap {
                    GeoPoint.fix(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                                 horizontalAccuracy: $0.horizontalAccuracy)
                },
                isFavorite: asset.isFavorite,
                isEdited: asset.hasAdjustments,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isHidden: asset.isHidden,
                isVideo: asset.mediaType != .image,
                originalFilename: name,
                burstId: asset.burstIdentifier
            ))
        }
        return assets
    }

    func uploadData(for id: String) async -> Data? {
        await image(for: id, maxPixel: 1024, allowNetwork: true)?.jpegData(compressionQuality: 0.9)
    }

    func image(for id: String, maxPixel: CGFloat, allowNetwork: Bool) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = allowNetwork
        options.isSynchronous = false
        let scale = maxPixel / CGFloat(max(asset.pixelWidth, asset.pixelHeight, 1))
        let target = CGSize(width: CGFloat(asset.pixelWidth) * min(1, scale),
                            height: CGFloat(asset.pixelHeight) * min(1, scale))
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func existing(_ ids: [String]) async -> Set<String> {
        var found: Set<String> = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            found.insert(asset.localIdentifier)
        }
        return found
    }
}
