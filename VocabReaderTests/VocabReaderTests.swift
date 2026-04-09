import XCTest
@testable import VocabReader

final class VocabReaderTests: XCTestCase {
    func testArticleParagraphExtractorSplitsStoryByBlankLinesAndPreservesInnerLineBreaks() {
        let extractor = ArticleParagraphExtractor()
        let article = Article(
            id: UUID(),
            scene: .story,
            content: "The apple rolled away.\nIt stopped by the chair.\n\nThe river was quiet.\nThe sky stayed bright.",
            targetWords: [
                VocabWord(id: "1", spelling: "apple"),
                VocabWord(id: "2", spelling: "river")
            ]
        )

        let paragraphs = extractor.extract(from: article)

        XCTAssertEqual(
            paragraphs.map(\.content),
            [
                "The apple rolled away.\nIt stopped by the chair.",
                "The river was quiet.\nThe sky stayed bright."
            ]
        )
    }

    func testArticleParagraphExtractorSplitsDialogueByEachTurn() {
        let extractor = ArticleParagraphExtractor()
        let article = Article(
            id: UUID(),
            scene: .dialogue,
            content: "A: Hello, apple.\nB: Hi, banana.\n\nA: The river is cold.",
            targetWords: [
                VocabWord(id: "1", spelling: "apple"),
                VocabWord(id: "2", spelling: "banana"),
                VocabWord(id: "3", spelling: "river")
            ]
        )

        let paragraphs = extractor.extract(from: article)

        XCTAssertEqual(
            paragraphs.map(\.content),
            [
                "A: Hello, apple.\nB: Hi, banana.",
                "A: The river is cold."
            ]
        )
    }

    func testArticleContentFormatterPreservesParagraphsAndDialogueLineBreaks() {
        let article = Article(
            id: UUID(),
            scene: .dialogue,
            content: "A: Hello, apple.\nB: Hi, banana.\n\nThey both smiled.",
            targetWords: [
                VocabWord(id: "1", spelling: "apple"),
                VocabWord(id: "2", spelling: "banana")
            ]
        )

        let formatted = ArticleContentFormatter().format(article: article)

        XCTAssertEqual(String(formatted.characters), article.content)
    }

    func testArticleContentFormatterAddsLinksOnlyToTargetWords() {
        let article = Article(
            id: UUID(),
            scene: .story,
            content: "Apple trees grow near a river.",
            targetWords: [VocabWord(id: "1", spelling: "river")]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(linkedRuns.count, 1)
        XCTAssertEqual(linkedRuns.first?.absoluteString, "word://river")
    }

    func testArticleContentFormatterAppendsInlineTranslationActionAtParagraphEnd() {
        let formatted = ArticleContentFormatter().formatParagraph(
            content: "A calm river moved slowly.",
            targetWords: [VocabWord(id: "1", spelling: "river")],
            paragraphIndex: 2,
            actionTitle: "翻译"
        )

        XCTAssertEqual(String(formatted.characters), "A calm river moved slowly. 翻译")
        let links = formatted.runs.compactMap(\.link)

        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.contains(URL(string: "word://river")!))
        XCTAssertTrue(links.contains(URL(string: "paragraph://2")!))
    }

    func testArticleContentFormatterUsesInlineActionTitleProvidedByViewState() {
        let formatted = ArticleContentFormatter().formatParagraph(
            content: "A calm river moved slowly.",
            targetWords: [],
            paragraphIndex: 2,
            actionTitle: "收起"
        )

        XCTAssertEqual(String(formatted.characters), "A calm river moved slowly. 收起")
        let links = formatted.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "paragraph://2")!])
    }
}
