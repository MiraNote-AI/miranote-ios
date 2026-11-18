import MiraNoteKit
import XCTest

/// api #95: our tokens in the real Keychain (the simulator's), under a
/// service of the test's own so the app's item is never touched.
final class KeychainTokenStoreTests: XCTestCase {
    private var service = ""
    private var store: KeychainTokenStore!

    override func setUp() {
        super.setUp()
        service = "ai.miranote.accounts.test-\(UUID().uuidString)"
        store = KeychainTokenStore(service: service)
    }

    override func tearDown() {
        store.save(nil)
        super.tearDown()
    }

    private func tokens(_ number: Int) -> AccountTokens {
        AccountTokens(accessToken: "access-\(number)", refreshToken: "refresh-\(number)", userID: "user-1",
                      accessExpiresAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(number)))
    }

    func testEmptyLoadsNothing() {
        XCTAssertNil(store.load())
    }

    func testSavedTokensComeBackAndAReplacementWins() {
        store.save(tokens(1))
        XCTAssertEqual(store.load(), tokens(1))
        store.save(tokens(2))
        XCTAssertEqual(store.load(), tokens(2), "a rotated pair replaces the old one")
    }

    func testSavingNilDeletes() {
        store.save(tokens(1))
        store.save(nil)
        XCTAssertNil(store.load())
    }

    func testAnotherStoreSeesTheSameItem() {
        store.save(tokens(1))
        XCTAssertEqual(KeychainTokenStore(service: service).load(), tokens(1), "kept across launches")
    }
}
