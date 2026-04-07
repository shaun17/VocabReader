import XCTest
@testable import VocabReader

final class KeychainTests: XCTestCase {
    let testKey = "test.vocabreader.key"

    override func tearDown() {
        Keychain.delete(key: testKey)
    }

    func testSaveAndLoad() {
        XCTAssertTrue(Keychain.save("secret", key: testKey))
        XCTAssertEqual(Keychain.load(key: testKey), "secret")
    }

    func testOverwrite() {
        Keychain.save("old", key: testKey)
        Keychain.save("new", key: testKey)
        XCTAssertEqual(Keychain.load(key: testKey), "new")
    }

    func testDeleteReturnsNil() {
        Keychain.save("value", key: testKey)
        Keychain.delete(key: testKey)
        XCTAssertNil(Keychain.load(key: testKey))
    }

    func testLoadMissingReturnsNil() {
        XCTAssertNil(Keychain.load(key: testKey))
    }
}
