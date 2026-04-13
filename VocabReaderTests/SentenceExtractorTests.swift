import XCTest
@testable import VocabReader

final class SentenceExtractorTests: XCTestCase {
    func testExtractsSentenceContainingWord() {
        let paragraph = "The sun rose slowly. The ephemeral beauty of cherry blossoms fades quickly. Birds sang in the trees."
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "The ephemeral beauty of cherry blossoms fades quickly.")
    }

    func testCaseInsensitiveMatch() {
        let paragraph = "She felt Ubiquitous pressure from all sides. It was overwhelming."
        let result = SentenceExtractor.sentence(containing: "ubiquitous", in: paragraph)
        XCTAssertEqual(result, "She felt Ubiquitous pressure from all sides.")
    }

    func testReturnsFirstMatchWhenMultipleSentences() {
        let paragraph = "Ephemeral joys are common. Another ephemeral moment passed."
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "Ephemeral joys are common.")
    }

    func testReturnsFullParagraphWhenNoSentenceBoundary() {
        let paragraph = "A single phrase with ephemeral inside"
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "A single phrase with ephemeral inside")
    }

    func testReturnsFullTextWhenWordNotFound() {
        let paragraph = "No matching word here."
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "No matching word here.")
    }
}
