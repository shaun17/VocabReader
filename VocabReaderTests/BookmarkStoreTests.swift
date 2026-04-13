import XCTest
@testable import VocabReader

final class BookmarkStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeStore() -> BookmarkStore {
        BookmarkStore(directory: tempDirectory)
    }

    func testAddBookmarkAppendsToList() {
        let store = makeStore()
        XCTAssertTrue(store.bookmarks.isEmpty)

        store.add(spelling: "ephemeral", sentence: "The ephemeral beauty fades quickly.")

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.spelling, "ephemeral")
        XCTAssertEqual(store.bookmarks.first?.sentence, "The ephemeral beauty fades quickly.")
    }

    func testRemoveBookmarkDeletesById() {
        let store = makeStore()
        store.add(spelling: "ephemeral", sentence: "Sentence one.")
        store.add(spelling: "ubiquitous", sentence: "Sentence two.")
        let idToRemove = store.bookmarks.first!.id

        store.remove(id: idToRemove)

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.spelling, "ubiquitous")
    }

    func testPersistenceRoundTrip() {
        let store1 = makeStore()
        store1.add(spelling: "ephemeral", sentence: "Sentence one.")
        store1.add(spelling: "ubiquitous", sentence: "Sentence two.")

        let store2 = makeStore()
        XCTAssertEqual(store2.bookmarks.count, 2)
        XCTAssertEqual(store2.bookmarks[0].spelling, "ephemeral")
        XCTAssertEqual(store2.bookmarks[1].spelling, "ubiquitous")
    }

    func testRemovePersistsAfterReload() {
        let store1 = makeStore()
        store1.add(spelling: "ephemeral", sentence: "Sentence one.")
        store1.add(spelling: "ubiquitous", sentence: "Sentence two.")
        store1.remove(id: store1.bookmarks.first!.id)

        let store2 = makeStore()
        XCTAssertEqual(store2.bookmarks.count, 1)
        XCTAssertEqual(store2.bookmarks.first?.spelling, "ubiquitous")
    }

    func testEmptyFileLoadsGracefully() {
        let store = makeStore()
        XCTAssertTrue(store.bookmarks.isEmpty)
    }
}
