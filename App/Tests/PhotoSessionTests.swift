import MiraNoteKit
import XCTest
@testable import MiraNote

/// Reopening a photo picks its editing session up again only when the photo
/// is unchanged since the session last saw it (#102).
final class PhotoSessionTests: XCTestCase {
    private let photo = UUID()
    private let ref = ImageRef(displayName: "p", fileName: "p.png")

    func testTheSamePhotoUnchangedContinues() {
        let session = PhotoSession(itemID: photo, original: ref)
        XCTAssertTrue(session.continues(photo, showing: ref))
    }

    func testAChangeMadeWhileThePanelWasClosedStartsAnew() {
        let session = PhotoSession(itemID: photo, original: ref)
        var restyled = ref
        restyled.fileName = "watercolor.png"
        XCTAssertFalse(session.continues(photo, showing: restyled), "a Mira restyle from the bar")
        var filtered = ref
        filtered.filterName = "bw"
        XCTAssertFalse(session.continues(photo, showing: filtered), "a Mira filter, or a header Undo")
    }

    func testThePanelsOwnEditCarriesOverToTheRealOriginal() {
        var session = PhotoSession(itemID: photo, original: ref)
        var edited = ref
        edited.fileName = "autumn.png"
        session.lastSeen = edited
        XCTAssertTrue(session.continues(photo, showing: edited))
        XCTAssertEqual(session.original, ref, "Compare and Revert still go back to the real original")
    }

    func testACaptionOrDescriptionIsNotAnEdit() {
        let session = PhotoSession(itemID: photo, original: ref)
        var described = ref
        described.displayName = "Lunch"
        described.summary = "a bowl of noodles"
        XCTAssertTrue(session.continues(photo, showing: described))
    }

    func testAnotherPhotoNeverContinues() {
        let session = PhotoSession(itemID: photo, original: ref)
        XCTAssertFalse(session.continues(UUID(), showing: ref))
    }
}
