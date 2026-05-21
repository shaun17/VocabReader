import XCTest
@testable import VocabReader

final class VocabReaderTests: XCTestCase {
    func testArticleParagraphExtractorSplitsNovelByBlankLinesAndPreservesInnerLineBreaks() {
        let extractor = ArticleParagraphExtractor()
        let article = Article(
            id: UUID(),
            scene: .novel,
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
            scene: .novel,
            content: "Apple trees grow near a river.",
            targetWords: [VocabWord(id: "1", spelling: "river")]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(linkedRuns.count, 1)
        XCTAssertEqual(linkedRuns.first?.absoluteString, "word://river")
    }

    func testArticleContentFormatterHandlesDuplicateTargetWordSpellings() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "Apple trees grow near another apple tree.",
            targetWords: [
                VocabWord(id: "1", spelling: "apple"),
                VocabWord(id: "2", spelling: "Apple")
            ]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(String(formatted.characters), article.content)
        XCTAssertEqual(linkedRuns.map(\.absoluteString), ["word://apple", "word://apple"])
    }

    func testArticleContentFormatterAppendsInlineTranslationActionAtParagraphEnd() {
        let formatted = ArticleContentFormatter().formatParagraph(
            content: "A calm river moved slowly.",
            targetWords: [VocabWord(id: "1", spelling: "river")],
            paragraphIndex: 2,
            translationActionTitle: "翻译",
            analysisActionTitle: "解析"
        )

        XCTAssertEqual(String(formatted.characters), "A calm river moved slowly. 翻译   解析")
        let links = formatted.runs.compactMap(\.link)

        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links.contains(URL(string: "word://river")!))
        XCTAssertTrue(links.contains(URL(string: "paragraph://2/translation")!))
        XCTAssertTrue(links.contains(URL(string: "paragraph://2/analysis")!))
    }

    func testArticleContentFormatterUsesInlineActionTitleProvidedByViewState() {
        let formatted = ArticleContentFormatter().formatParagraph(
            content: "A calm river moved slowly.",
            targetWords: [],
            paragraphIndex: 2,
            translationActionTitle: "收起",
            analysisActionTitle: "解析"
        )

        XCTAssertEqual(String(formatted.characters), "A calm river moved slowly. 收起   解析")
        let links = formatted.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "paragraph://2/translation")!, URL(string: "paragraph://2/analysis")!])
    }

    @MainActor
    func testArticleAudioPlayerIgnoresSeekWhenArticleHasNoParagraphs() {
        let speechService = MockSpeechService()
        let player = ArticleAudioPlayerViewModel(paragraphs: [], speechService: speechService)

        player.seek(to: 0.5)

        XCTAssertEqual(player.playbackState, .idle)
        XCTAssertNil(player.currentParagraphIndex)
        XCTAssertEqual(player.progress, 0)
        XCTAssertEqual(speechService.stopCallCount, 0)
        XCTAssertTrue(speechService.spokenTexts.isEmpty)
    }
}

private final class MockSpeechService: SpeechServiceProtocol {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCallCount = 0
    var isSpeaking = false
    var isPaused = false

    func speak(
        _ text: String,
        rate: Float,
        onProgress: @escaping (Double) -> Void,
        onFinish: @escaping () -> Void
    ) {
        spokenTexts.append(text)
        isSpeaking = true
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func stop() {
        stopCallCount += 1
        isSpeaking = false
    }
}
