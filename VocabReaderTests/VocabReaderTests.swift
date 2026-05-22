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

    func testArticleContentFormatterHighlightsInflectedTargetWordForms() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "The manager was concerned about recurring concerns.",
            targetWords: [
                VocabWord(id: "1", spelling: "concern"),
                VocabWord(id: "2", spelling: "recur")
            ]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(String(formatted.characters), article.content)
        XCTAssertEqual(
            linkedRuns.map(\.absoluteString),
            ["word://concern", "word://recur", "word://concern"]
        )
    }

    func testArticleContentFormatterHighlightsRegularFormsWhenFinalConsonantDoesNotDouble() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "The store opened before the opening meeting.",
            targetWords: [VocabWord(id: "1", spelling: "open")]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(String(formatted.characters), article.content)
        XCTAssertEqual(linkedRuns.map(\.absoluteString), ["word://open", "word://open"])
    }

    func testArticleContentFormatterHighlightsBaseFormWhenTargetWordIsInflected() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "One concern returned after the meeting.",
            targetWords: [VocabWord(id: "1", spelling: "concerns")]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(String(formatted.characters), article.content)
        XCTAssertEqual(linkedRuns.map(\.absoluteString), ["word://concerns"])
    }

    func testArticleContentFormatterDoesNotTreatLexicalSEndingsAsPluralForms() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "A new report discussed the news.",
            targetWords: [VocabWord(id: "1", spelling: "news")]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(String(formatted.characters), article.content)
        XCTAssertEqual(linkedRuns.map(\.absoluteString), ["word://news"])
    }

    func testArticleContentFormatterKeepsParagraphActionsOutOfSelectableText() {
        let formatted = ArticleContentFormatter().formatParagraph(
            content: "A calm river moved slowly.",
            targetWords: [VocabWord(id: "1", spelling: "river")]
        )

        XCTAssertEqual(String(formatted.characters), "A calm river moved slowly.")
        let links = formatted.runs.compactMap(\.link)

        XCTAssertEqual(links, [URL(string: "word://river")!])
    }

    func testParagraphSupplementDrawerStateKeepsContentUntilCloseFinishes() {
        var state = ParagraphSupplementDrawerState<String>()

        let openMutation = state.update(with: "解析内容")
        let closeMutation = state.update(with: nil)

        XCTAssertEqual(openMutation, .open(token: 1))
        XCTAssertEqual(closeMutation, .close(token: 2))
        XCTAssertEqual(state.renderedSupplement, "解析内容")
        XCTAssertFalse(state.isOpen)

        state.finishClose(token: 2)

        XCTAssertNil(state.renderedSupplement)
    }

    func testParagraphSupplementDrawerStateIgnoresStaleCloseCompletion() {
        var state = ParagraphSupplementDrawerState<String>()

        _ = state.update(with: "旧解析")
        let closeMutation = state.update(with: nil)
        _ = state.update(with: "新解析")

        if case let .close(token) = closeMutation {
            state.finishClose(token: token)
        } else {
            XCTFail("关闭补充内容时应该返回 close mutation")
        }

        XCTAssertEqual(state.renderedSupplement, "新解析")
        XCTAssertTrue(state.isOpen)
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
