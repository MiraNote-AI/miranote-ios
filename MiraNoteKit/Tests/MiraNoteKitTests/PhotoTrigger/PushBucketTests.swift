import XCTest
@testable import MiraNoteKit

final class PushBucketTests: XCTestCase {
    func testCaseOrder() {
        XCTAssertEqual(PushBucket.allCases, [.food, .scenery, .animal, .city, .indoor, .event, .other])
    }

    func testEachCategoryMapsToItsBucket() {
        let expected: [BroadCategory: PushBucket] = [
            .food_drink: .food, .tableware: .food,
            .sky: .scenery, .plant: .scenery, .water: .scenery,
            .animal: .animal,
            .built: .city, .street: .city, .vehicle: .city,
            .interior: .indoor,
            .event: .event, .recreation: .event,
            .art: .other, .document: .other
        ]
        for category in BroadCategory.allCases where category != .people {
            XCTAssertEqual(category.bucket, expected[category], "\(category)")
        }
    }

    func testPeopleDoNotVote() {
        XCTAssertNil(BroadCategory.people.bucket)
        XCTAssertEqual(PushBucket.majority(of: [[.people, .animal], [.people, .animal], [.people]]), .animal)
    }

    func testOnlyPeopleIsOther() {
        XCTAssertEqual(PushBucket.majority(of: [[.people], [.people]]), .other)
    }

    func testNothingRecognisedIsOther() {
        XCTAssertEqual(PushBucket.majority(of: []), .other)
        XCTAssertEqual(PushBucket.majority(of: [[], []]), .other)
    }

    func testPhotoWithoutVoteCountsAsOther() {
        XCTAssertEqual(PushBucket.majority(of: [[], [], [.food_drink]]), .other)
    }

    func testTieGoesToEarlierBucket() {
        XCTAssertEqual(PushBucket.majority(of: [[.sky], [.food_drink]]), .food)
        XCTAssertEqual(PushBucket.majority(of: [[.event], [.animal]]), .animal)
    }

    func testPhotoVotesOncePerBucket() {
        // One sky+plant photo is one scenery vote, so two food photos win.
        XCTAssertEqual(PushBucket.majority(of: [[.sky, .plant], [.food_drink], [.tableware]]), .food)
        XCTAssertEqual(PushBucket.majority(of: [[.sky, .plant, .water], [.animal], [.animal]]), .animal)
    }

    func testPhotoBucketIsFirstInBucketOrder() {
        func photo(_ broad: Set<BroadCategory>) -> PhotoAnalysis {
            PhotoAnalysis(id: "p", labels: [], broad: broad, faces: 0, aesthetics: nil,
                          isUtility: false, featurePrint: nil)
        }
        XCTAssertEqual(photo([.sky, .food_drink]).photoBucket, .food)
        XCTAssertEqual(photo([.street, .interior]).photoBucket, .city)
        XCTAssertEqual(photo([.people]).photoBucket, .other)
        XCTAssertEqual(photo([]).photoBucket, .other)
    }

    func testCatalogKeys() {
        XCTAssertEqual(PushBucket.allCases.map(\.catalogKey), [
            "Food and drink", "Nature and scenery", "Pets and animals", "City and streets",
            "Indoors and home", "Events and shows", "Other"
        ])
    }
}
