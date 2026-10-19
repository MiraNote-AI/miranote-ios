import Photos
import SwiftUI
import UIKit

/// A photo in the Recents grid, by its library identifier.
struct LibraryPhoto: Identifiable, Hashable {
    let id: String
}

/// The Recents grid's photos (handoff screen 24): the newest library photos
/// through PhotoKit -- the system picker cannot draw the design's r18 cells,
/// ink selection ring and order badges. -UITEST runs read nine painted
/// samples instead, so selection flows are deterministic and need no
/// permission.
@MainActor
@Observable
final class RecentPhotos {
    enum Access: Equatable {
        /// `limited`: only the photos the user chose to share.
        case unknown, granted, limited, denied
    }

    private(set) var access: Access = .unknown
    private(set) var photos: [LibraryPhoto] = []

    private let usesSamples: Bool
    private let imageManager = PHCachingImageManager()
    private var assets: [String: PHAsset] = [:]
    private var thumbnails: [String: UIImage] = [:]
    /// Refetches when the library changes -- photos shared through the
    /// limited picker show without reopening the tool.
    /// Set once on the main actor; read again only by deinit.
    @ObservationIgnored nonisolated(unsafe) private var observer: LibraryObserver?

    init() {
        #if DEBUG
        usesSamples = ProcessInfo.processInfo.arguments.contains("-UITEST")
            && !ProcessInfo.processInfo.arguments.contains("-PHOTOKIT")
        #else
        usesSamples = false
        #endif
    }

    deinit {
        if let observer { PHPhotoLibrary.shared().unregisterChangeObserver(observer) }
    }

    /// Asks once and fetches the newest 60, then follows library changes.
    func load() async {
        if usesSamples {
            photos = Self.sampleColors.indices.map { LibraryPhoto(id: "sample-\($0)") }
            access = .granted
            #if DEBUG
            // -UITEST: the limited-access sheet, on the same samples.
            if ProcessInfo.processInfo.arguments.contains("-PHOTOS-LIMITED") { access = .limited }
            #endif
            return
        }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            access = .denied
            return
        }
        fetch()
        access = status == .limited ? .limited : .granted
        if observer == nil {
            let observer = LibraryObserver { [weak self] in
                Task { @MainActor in self?.fetch() }
            }
            PHPhotoLibrary.shared().register(observer)
            self.observer = observer
        }
    }

    /// Limited access: the system sheet that shares more photos with the
    /// app; the change observer brings them into the grid.
    func shareMorePhotos() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private func fetch() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 60
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetched: [LibraryPhoto] = []
        result.enumerateObjects { asset, _, _ in
            self.assets[asset.localIdentifier] = asset
            fetched.append(LibraryPhoto(id: asset.localIdentifier))
        }
        photos = fetched
    }

    func thumbnail(_ photo: LibraryPhoto, side: CGFloat) async -> UIImage? {
        if let cached = thumbnails[photo.id] { return cached }
        let image: UIImage?
        if usesSamples {
            image = Self.sample(photo).flatMap(UIImage.init(data:))
        } else if let asset = assets[photo.id] {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let pixels = side * 3
            image = await withCheckedContinuation { continuation in
                imageManager.requestImage(
                    for: asset, targetSize: CGSize(width: pixels, height: pixels),
                    contentMode: .aspectFill, options: options
                ) { image, _ in continuation.resume(returning: image) }
            }
        } else {
            image = nil
        }
        thumbnails[photo.id] = image
        return image
    }

    /// The picked photos' bytes, downscaled for the canvas, in pick order.
    func data(for picks: [LibraryPhoto]) async -> [Data] {
        #if DEBUG
        // -UITEST: `-IMPORT_DELAY <ms>` stands in for slow iCloud originals.
        let delay = UserDefaults.standard.integer(forKey: "IMPORT_DELAY")
        if usesSamples, delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
        #endif
        var result: [Data] = []
        for pick in picks {
            let raw: Data?
            if usesSamples {
                raw = Self.sample(pick)
            } else if let asset = assets[pick.id] {
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.version = .current
                raw = await withCheckedContinuation { continuation in
                    imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                        continuation.resume(returning: data)
                    }
                }
            } else {
                raw = nil
            }
            if let raw, let scaled = UIImage(data: raw)?.downscaled() { result.append(scaled) }
        }
        return result
    }

    /// PhotoKit calls back on its own queue; the owner hops to the main actor.
    private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
        let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }

        func photoLibraryDidChange(_ changeInstance: PHChange) {
            onChange()
        }
    }

    // MARK: -UITEST samples

    private static let sampleColors: [UIColor] = [
        UIColor(red: 0.62, green: 0.20, blue: 0.20, alpha: 1),
        UIColor(red: 0.84, green: 0.80, blue: 0.74, alpha: 1),
        UIColor(red: 0.86, green: 0.42, blue: 0.42, alpha: 1),
        UIColor(red: 0.70, green: 0.72, blue: 0.66, alpha: 1),
        UIColor(red: 0.89, green: 0.84, blue: 0.74, alpha: 1),
        UIColor(red: 0.77, green: 0.33, blue: 0.27, alpha: 1),
        UIColor(red: 0.36, green: 0.42, blue: 0.34, alpha: 1),
        UIColor(red: 0.66, green: 0.70, blue: 0.64, alpha: 1),
        UIColor(red: 0.88, green: 0.82, blue: 0.70, alpha: 1),
    ]

    private static func sample(_ photo: LibraryPhoto) -> Data? {
        guard let index = Int(photo.id.dropFirst("sample-".count)), sampleColors.indices.contains(index) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: format).pngData { context in
            sampleColors[index].setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
    }
}
