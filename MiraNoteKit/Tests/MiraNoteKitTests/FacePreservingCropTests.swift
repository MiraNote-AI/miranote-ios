import XCTest
@testable import MiraNoteKit

final class FacePreservingCropTests: XCTestCase {
    private let phone = CGSize(width: 400, height: 860)
    private let landscape = CGSize(width: 4000, height: 3000)

    func testNoFacesFillsCentered() {
        let frame = FacePreservingCrop.frame(imageSize: landscape, faces: .none, in: phone)
        XCTAssertEqual(frame.height, 860, accuracy: 0.01)
        XCTAssertEqual(frame.midX, 200, accuracy: 0.01)
    }

    /// A face near the left edge of a landscape photo: the plain centered
    /// fill would cut it, the crop slides to keep it whole.
    func testAFaceNearTheEdgeStaysWhole() {
        let face = CGRect(x: 0.05, y: 0.3, width: 0.1, height: 0.15)
        let frame = FacePreservingCrop.frame(imageSize: landscape, faces: .found(face), in: phone)
        let onScreen = CGRect(x: frame.minX + face.minX * frame.width, y: frame.minY + face.minY * frame.height,
                              width: face.width * frame.width, height: face.height * frame.height)
        XCTAssertTrue(CGRect(origin: .zero, size: phone).contains(onScreen))
        // Still a fill: the image covers the screen.
        XCTAssertLessThanOrEqual(frame.minX, 0)
        XCTAssertGreaterThanOrEqual(frame.maxX, phone.width)
    }

    /// Two people at either end of a landscape photo cannot both fit a
    /// portrait fill, so the whole photo is shown.
    func testFacesTooWideFallBackToFit() {
        let faces = CGRect(x: 0.05, y: 0.3, width: 0.9, height: 0.2)
        let frame = FacePreservingCrop.frame(imageSize: landscape, faces: .found(faces), in: phone)
        XCTAssertEqual(frame.width, 400, accuracy: 0.01)
        XCTAssertLessThan(frame.height, phone.height)
    }

    func testLandscapeAndSquareShowWholePortraitFills() {
        XCTAssertTrue(FacePreservingCrop.showsWhole(imageSize: CGSize(width: 4000, height: 3000)))
        XCTAssertTrue(FacePreservingCrop.showsWhole(imageSize: CGSize(width: 3000, height: 3000)))
        XCTAssertFalse(FacePreservingCrop.showsWhole(imageSize: CGSize(width: 3000, height: 4000)))
        XCTAssertFalse(FacePreservingCrop.showsWhole(imageSize: CGSize(width: 1080, height: 1920)))
        XCTAssertFalse(FacePreservingCrop.showsWhole(imageSize: .zero))
    }

    func testUnknownFacesFit() {
        let frame = FacePreservingCrop.frame(imageSize: landscape, faces: .unknown, in: phone)
        XCTAssertEqual(frame.width, 400, accuracy: 0.01)
        XCTAssertEqual(frame.midY, 430, accuracy: 0.01)
    }
}
