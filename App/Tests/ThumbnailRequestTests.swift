import Photos
import UIKit
import XCTest
@testable import MiraNote

/// #204: a Recents cell scrolled away cancels its PhotoKit thumbnail
/// request, and PhotoKit may still answer after the cancel. The waiting
/// continuation must resume exactly once either way -- a second resume
/// traps, so each of these would crash the test run rather than fail.
final class ThumbnailRequestTests: XCTestCase {
    /// Holds each request's result handler until the test answers it.
    private final class HeldImageManager: PHImageManager, @unchecked Sendable {
        var handlers: [PHImageRequestID: (UIImage?, [AnyHashable: Any]?) -> Void] = [:]
        var requested = 0
        var cancelled: [PHImageRequestID] = []
        /// Answer inside `requestImage` itself, as PhotoKit may for a
        /// cached image.
        var answersAtOnce: UIImage?

        override func requestImage(
            for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
            options: PHImageRequestOptions?,
            resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
        ) -> PHImageRequestID {
            requested += 1
            let id = PHImageRequestID(requested)
            handlers[id] = resultHandler
            if let answersAtOnce { resultHandler(answersAtOnce, nil) }
            return id
        }

        override func cancelImageRequest(_ requestID: PHImageRequestID) {
            cancelled.append(requestID)
        }

        func answer(_ image: UIImage?) {
            for handler in handlers.values { handler(image, nil) }
        }
    }

    private let size = CGSize(width: 276, height: 276)

    func testAnAnswerResumesOnceAndALaterOneIsDropped() async {
        let manager = HeldImageManager()
        let request = RecentPhotos.ThumbnailRequest(manager: manager)
        let first = UIImage()
        let image = await withCheckedContinuation { continuation in
            request.start(continuation, asset: PHAsset(), size: size)
            manager.answer(first)
            manager.answer(UIImage())
        }
        XCTAssertTrue(image === first)
        XCTAssertEqual(manager.cancelled, [])
    }

    func testACancelResumesWithNothingAndDropsPhotoKitsLateAnswer() async {
        let manager = HeldImageManager()
        let request = RecentPhotos.ThumbnailRequest(manager: manager)
        let image = await withCheckedContinuation { continuation in
            request.start(continuation, asset: PHAsset(), size: size)
            request.cancel()
            manager.answer(UIImage())
        }
        XCTAssertNil(image)
        XCTAssertEqual(manager.cancelled, [1], "PhotoKit is told to drop the request")
    }

    func testACancelBeforeTheStartAsksPhotoKitForNothing() async {
        let manager = HeldImageManager()
        let request = RecentPhotos.ThumbnailRequest(manager: manager)
        request.cancel()
        let image = await withCheckedContinuation { continuation in
            request.start(continuation, asset: PHAsset(), size: size)
        }
        XCTAssertNil(image)
        XCTAssertEqual(manager.requested, 0)
    }

    func testAnAnswerInsideTheRequestThenACancelResumesOnce() async {
        let manager = HeldImageManager()
        let cached = UIImage()
        manager.answersAtOnce = cached
        let request = RecentPhotos.ThumbnailRequest(manager: manager)
        let image = await withCheckedContinuation { continuation in
            request.start(continuation, asset: PHAsset(), size: size)
            request.cancel()
        }
        XCTAssertTrue(image === cached)
    }
}
