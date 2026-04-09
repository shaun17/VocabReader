import XCTest
@testable import VocabReader

final class KeychainTests: XCTestCase {
    let testKey = "test.vocabreader.key"
    let store = KeychainStore(
        service: "com.vocabreader.secure-storage.tests.keychain-tests",
        defaults: UserDefaults(suiteName: "com.vocabreader.tests.keychain-tests") ?? .standard,
        fallbackPrefix: "com.vocabreader.secure-storage.tests.keychain-tests.fallback."
    )

    override func tearDown() {
        store.delete(key: testKey)
    }

    func testSaveAndLoad() {
        XCTAssertTrue(store.save("secret", key: testKey))
        XCTAssertEqual(store.load(key: testKey), "secret")
    }

    func testOverwrite() {
        store.save("old", key: testKey)
        store.save("new", key: testKey)
        XCTAssertEqual(store.load(key: testKey), "new")
    }

    func testDeleteReturnsNil() {
        store.save("value", key: testKey)
        store.delete(key: testKey)
        XCTAssertNil(store.load(key: testKey))
    }

    func testLoadMissingReturnsNil() {
        XCTAssertNil(store.load(key: testKey))
    }
}
