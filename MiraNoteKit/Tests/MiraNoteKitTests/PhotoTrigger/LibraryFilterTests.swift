import XCTest
@testable import MiraNoteKit

/// Grouping step 1 (acceptance B2): which library photos take part.
final class LibraryFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_761_900_000)

    private func asset(
        _ id: String = "a",
        name: String? = "IMG_0001.HEIC",
        takenAt: Date? = Date(timeIntervalSince1970: 1_761_000_000),
        location: GeoPoint? = GeoPoint(lat: 32.8, lon: -96.7),
        screenshot: Bool = false, hidden: Bool = false, video: Bool = false
    ) -> LibraryAsset {
        LibraryAsset(id: id, takenAt: takenAt, location: location, isFavorite: false, isEdited: false,
                     isScreenshot: screenshot, isHidden: hidden, isVideo: video,
                     originalFilename: name, burstId: nil)
    }

    func testScreenshotHiddenVideoExcluded() {
        XCTAssertTrue(LibraryFilter.eligible(asset(), now: now))
        XCTAssertFalse(LibraryFilter.eligible(asset(screenshot: true), now: now))
        XCTAssertFalse(LibraryFilter.eligible(asset(hidden: true), now: now))
        XCTAssertFalse(LibraryFilter.eligible(asset(video: true), now: now))
    }

    func testNoGpsCameraPhotoKept() {
        XCTAssertTrue(LibraryFilter.eligible(asset(location: nil), now: now))
    }

    func testMmexportIsNotCamera() {
        XCTAssertEqual(CameraOrigin.classify(filename: "mmexport1697000000000.jpg"), .notCamera)
        XCTAssertEqual(CameraOrigin.classify(filename: "Screenshot 2026-10-01 at 10.00.00.png"), .notCamera)
        XCTAssertEqual(CameraOrigin.classify(filename: "wx_camera_1697.jpg"), .notCamera)
        XCTAssertEqual(CameraOrigin.classify(filename: "Weixin Image_2026.jpg"), .notCamera)
        XCTAssertEqual(CameraOrigin.classify(filename: "image-Download-3.jpeg"), .notCamera)
        XCTAssertEqual(CameraOrigin.classify(filename: "3F2504E0-4F89-11D3-9A0C-0305E82C3301.jpeg"), .notCamera)
        XCTAssertFalse(LibraryFilter.eligible(asset(name: "mmexport1697000000000.jpg"), now: now))
    }

    func testImgIsCamera() {
        for name in ["IMG_0577.HEIC", "img_1.jpg", "DSC01234.JPG", "_DSC9.ARW", "PXL_20261001_1.jpg", "DJI_0001.JPG"] {
            XCTAssertEqual(CameraOrigin.classify(filename: name), .camera, name)
        }
    }

    func testUnknownNameKept() {
        XCTAssertEqual(CameraOrigin.classify(filename: "holiday.jpg"), .unknown)
        XCTAssertEqual(CameraOrigin.classify(filename: nil), .unknown)
        XCTAssertTrue(LibraryFilter.eligible(asset(name: "holiday.jpg"), now: now))
        XCTAssertTrue(LibraryFilter.eligible(asset(name: nil), now: now))
    }

    /// Review focus 1: no date, or a date ahead of the clock, never groups.
    func testPhotoWithoutDateIsExcluded() {
        XCTAssertFalse(LibraryFilter.eligible(asset(takenAt: nil), now: now))
        XCTAssertFalse(LibraryFilter.eligible(asset(takenAt: now.addingTimeInterval(86_400 * 30)), now: now))
    }

    func testSignIsNotDocument() {
        XCTAssertEqual(BroadCategory.from(labels: ["sign"]), [])
        XCTAssertEqual(BroadCategory.from(labels: ["document", "printed_page"]), [.document])
        XCTAssertEqual(BroadCategory.from(labels: ["food", "utensil", "people", "nonsense"]),
                       [.food_drink, .tableware, .people])
        XCTAssertEqual(BroadCategory.allCases.count, 15)
    }

    func testDistanceIsHaversine() {
        let dallas = GeoPoint(lat: 32.7767, lon: -96.7970)
        let fortWorth = GeoPoint(lat: 32.7555, lon: -97.3308)
        XCTAssertEqual(dallas.km(to: fortWorth), 49.9, accuracy: 0.5)
        XCTAssertEqual(dallas.km(to: dallas), 0, accuracy: 0.0001)
    }
}

final class AnalysisStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func analysis(_ id: String) -> PhotoAnalysis {
        PhotoAnalysis(id: id, labels: ["food", "sign"], broad: [.food_drink], faces: 2,
                      aesthetics: 0.4, isUtility: false, featurePrint: Data([1, 2, 3]))
    }

    func testStoreRoundTripsOneFilePerPhoto() throws {
        let store = AnalysisStore(directory: folder)
        // Real localIdentifiers carry slashes.
        let ids = ["ABC-1/L0/001", "DEF-2/L0/001"]
        for id in ids { try store.save(analysis(id)) }
        XCTAssertEqual(store.load("ABC-1/L0/001"), analysis("ABC-1/L0/001"))
        XCTAssertNil(store.load("missing"))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(store.analyzedIds(), Set(ids))
    }

    func testStoreSurvivesPartialRun() throws {
        let first = AnalysisStore(directory: folder)
        for index in 0..<3 { try first.save(analysis("photo-\(index)")) }
        // A new launch: a fresh store over the same folder.
        let second = AnalysisStore(directory: folder)
        XCTAssertEqual(second.analyzedIds().count, 3)
        let todo = (0..<5).map { "photo-\($0)" }.filter { !second.analyzedIds().contains($0) }
        XCTAssertEqual(todo, ["photo-3", "photo-4"])
    }

    func testEmptyFolderHasNothing() {
        XCTAssertEqual(AnalysisStore(directory: folder).analyzedIds(), [])
    }
}
