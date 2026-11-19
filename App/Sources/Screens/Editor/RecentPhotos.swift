import Photos
import SwiftUI
import UIKit

/// A photo in the Recents grid, by its library identifier.
struct LibraryPhoto: Identifiable, Hashable {
    let id: String
}

/// The Recents grid's photos (handoff screen 24): the newest library photos
/// through PhotoKit -- the system picker cannot draw the design's r18 cells,
/// ink selection ring and order badges. -UITEST runs read 120 painted
/// samples instead (more than a page), so selection and scroll flows are
/// deterministic and need no permission.
@MainActor
@Observable
final class RecentPhotos {
    enum Access: Equatable {
        /// `limited`: only the photos the user chose to share.
        case unknown, granted, limited, denied
    }

    private(set) var access: Access = .unknown
    /// The pages shown so far; `loadMore` adds the next.
    private(set) var photos: [LibraryPhoto] = []

    private let usesSamples: Bool
    private let imageManager = PHCachingImageManager()
    /// The shown photos' assets, by identifier.
    private var assets: [String: PHAsset] = [:]
    /// Enough for a few screens of the grid; visible cells hold their own.
    private let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()
    /// How many photos there are to page through, and the identifiers in
    /// a range of them (filling `assets` for those).
    private var total = 0
    private var page: (Range<Int>) -> [String] = { _ in [] }
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

    /// Asks once and shows the newest page, then follows library changes.
    func load() async {
        if usesSamples {
            show(total: Self.sampleCount) { range in range.map { "sample-\($0)" } }
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
        access = status == .limited ? .limited : .granted
        fetch()
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

    /// The next page, when one is left.
    func loadMore() {
        guard photos.count < total else { return }
        let end = min(photos.count + Self.pageSize, total)
        photos += page(photos.count..<end).map(LibraryPhoto.init(id:))
    }

    /// The photos published a page at a time, so a big library opens as
    /// fast as a small one.
    nonisolated static let pageSize = 90

    /// A fresh source: as many photos as showed before (a library change
    /// keeps the user's place), at least a page.
    private func show(total: Int, page: @escaping (Range<Int>) -> [String]) {
        self.total = total
        self.page = page
        photos = page(0..<min(max(photos.count, Self.pageSize), total)).map(LibraryPhoto.init(id:))
    }

    private func fetch() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // A lazy result: only the pages shown are read.
        let result = PHAsset.fetchAssets(with: .image, options: options)
        assets = [:]
        guard access == .limited else {
            show(total: result.count) { [weak self] range in
                let found = result.objects(at: IndexSet(integersIn: range))
                for asset in found { self?.assets[asset.localIdentifier] = asset }
                return found.map(\.localIdentifier)
            }
            return
        }
        // Limited: every shared photo, however old, sorted by when it was
        // shared -- the user picked them, so there are few.
        var ids: [String] = []
        result.enumerateObjects { asset, _, _ in
            self.assets[asset.localIdentifier] = asset
            ids.append(asset.localIdentifier)
        }
        let defaults = UserDefaults.standard
        let stored = defaults.dictionary(forKey: Self.sharedAtKey) as? [String: Date]
        let shared = Self.sharedOrder(ids, sharedAt: stored, now: Date())
        defaults.set(shared.sharedAt, forKey: Self.sharedAtKey)
        show(total: shared.ids.count) { range in Array(shared.ids[range]) }
    }

    /// When each photo was first seen shared, by library identifier.
    private static let sharedAtKey = "photos.limited.sharedAt"

    /// Limited access: PhotoKit does not say when a photo was shared, so a
    /// photo first seen now counts as shared now, and the grid shows the
    /// latest shares first (#167). `ids` come newest taken first; the
    /// photos already shared before anything was recorded (`sharedAt` nil)
    /// keep that order, below any later share. A photo no longer shared
    /// is forgotten, so sharing it again brings it back to the top.
    nonisolated static func sharedOrder(
        _ ids: [String], sharedAt: [String: Date]?, now: Date
    ) -> (ids: [String], sharedAt: [String: Date]) {
        var seen: [String: Date] = [:]
        for id in ids { seen[id] = sharedAt?[id] ?? (sharedAt == nil ? .distantPast : now) }
        let ordered = ids.enumerated()
            .sorted { lhs, rhs in
                let left = seen[lhs.element, default: .distantPast], right = seen[rhs.element, default: .distantPast]
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        return (ordered, seen)
    }

    /// The cell's thumbnail; a cell scrolled away (its task cancelled)
    /// drops the PhotoKit request, so a fling queues no iCloud downloads.
    func thumbnail(_ photo: LibraryPhoto, side: CGFloat) async -> UIImage? {
        if let cached = thumbnails.object(forKey: photo.id as NSString) { return cached }
        let image: UIImage?
        if usesSamples {
            image = Self.sample(photo).flatMap(UIImage.init(data:))
        } else if let asset = assets[photo.id] {
            let request = ThumbnailRequest(manager: imageManager)
            let pixels = side * 3
            image = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    request.start(continuation, asset: asset, size: CGSize(width: pixels, height: pixels))
                }
            } onCancel: {
                request.cancel()
            }
        } else {
            image = nil
        }
        if let image { thumbnails.setObject(image, forKey: photo.id as NSString) }
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
            } else if let asset = assets[pick.id] ?? Self.asset(pick.id) {
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

    /// A pick the shown pages no longer hold is still in the library: a
    /// library change refills `assets` for the shown count only, so new
    /// photos on top push the last shown ones (and a pick there) out.
    private static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// One thumbnail request PhotoKit can be told to drop. The continuation
    /// resumes exactly once: with the image, or with nil when the cell's
    /// task is cancelled first (PhotoKit may still answer after a cancel).
    /// Not private: ThumbnailRequestTests holds PhotoKit's answers.
    final class ThumbnailRequest: @unchecked Sendable {
        private let manager: PHImageManager
        private let lock = NSLock()
        private var continuation: CheckedContinuation<UIImage?, Never>?
        private var id: PHImageRequestID?
        private var cancelled = false

        init(manager: PHImageManager) {
            self.manager = manager
        }

        func start(_ continuation: CheckedContinuation<UIImage?, Never>, asset: PHAsset, size: CGSize) {
            lock.lock()
            guard !cancelled else {
                lock.unlock()
                continuation.resume(returning: nil)
                return
            }
            self.continuation = continuation
            lock.unlock()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let id = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                          options: options) { [weak self] image, _ in self?.finish(image) }
            lock.lock()
            self.id = id
            let lateCancel = cancelled
            lock.unlock()
            if lateCancel { manager.cancelImageRequest(id) }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let id = self.id
            lock.unlock()
            if let id { manager.cancelImageRequest(id) }
            finish(nil)
        }

        private func finish(_ image: UIImage?) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: image)
        }
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

    private static let sampleCount = 120

    /// Painted in turn, so neighbours differ.
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
        guard let index = Int(photo.id.dropFirst("sample-".count)), (0..<sampleCount).contains(index) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // `-SAMPLE_SHAPES`: portrait and landscape in turn, a pale disc in
        // the middle, so layout crops show.
        let shapes = ProcessInfo.processInfo.arguments.contains("-SAMPLE_SHAPES")
        let size = !shapes ? CGSize(width: 120, height: 120)
            : index % 2 == 0 ? CGSize(width: 300, height: 400) : CGSize(width: 400, height: 260)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            sampleColors[index % sampleColors.count].setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if shapes {
                UIColor.white.withAlphaComponent(0.6).setFill()
                let side = min(size.width, size.height) * 0.4
                context.cgContext.fillEllipse(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                                                         width: side, height: side))
            }
        }
    }
}
