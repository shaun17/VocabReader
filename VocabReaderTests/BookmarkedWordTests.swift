import XCTest
@testable import VocabReader

final class BookmarkedWordTests: XCTestCase {
    func testRoundTripCodable() throws {
        let word = BookmarkedWord(
            id: UUID(),
            spelling: "ephemeral",
            sentence: "The ephemeral beauty of cherry blossoms fades quickly.",
            bookmarkedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(BookmarkedWord.self, from: data)

        XCTAssertEqual(decoded.id, word.id)
        XCTAssertEqual(decoded.spelling, word.spelling)
        XCTAssertEqual(decoded.sentence, word.sentence)
        XCTAssertEqual(decoded.bookmarkedAt, word.bookmarkedAt)
    }
}
