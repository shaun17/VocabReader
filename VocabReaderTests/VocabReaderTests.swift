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

    func testArticleVocabularyMarkupParserRemovesUnclosedVocabularyTag() {
        let word = VocabWord(id: "1", spelling: "delay")
        let parsed = ArticleVocabularyMarkupParser().parse(
            content: "We can proceed without <vocab id=\"1\">delay today.",
            targetWords: [word]
        )

        XCTAssertEqual(parsed.content, "We can proceed without delay today.")
        XCTAssertFalse(parsed.content.contains("<vocab"))
        XCTAssertEqual(parsed.occurrences.map(\.surfaceText), ["delay"])
        XCTAssertTrue(parsed.missingWords.isEmpty)
    }

    func testArticleVocabularyMarkupParserRemovesMalformedVocabularyTagWithoutClosingAngle() {
        let words = [
            VocabWord(id: "1", spelling: "invitation"),
            VocabWord(id: "2", spelling: "exit")
        ]
        let parsed = ArticleVocabularyMarkupParser().parse(
            content: "A: The <vocab id=\"broken invitation changed the exit plan.",
            targetWords: words
        )

        XCTAssertEqual(parsed.content, "A: The invitation changed the exit plan.")
        XCTAssertFalse(parsed.content.contains("<vocab"))
        XCTAssertEqual(parsed.missingWords.map(\.spelling), [])
    }

    /// LLM 即使额外给目标词加 Markdown 粗体，最终正文也不能泄漏星号，词汇范围仍要对齐清理后的文本。
    func testArticleVocabularyMarkupParserRemovesMarkdownEmphasisAroundVocabularyMarker() {
        let word = VocabWord(id: "phrase-1", spelling: "office table")
        let parsed = ArticleVocabularyMarkupParser().parse(
            content: "Pass me the **<vocab id=\"w1\">office table</vocab>** clutter.",
            targetWords: [word],
            markerWordByID: ["w1": word]
        )

        XCTAssertEqual(parsed.content, "Pass me the office table clutter.")
        XCTAssertEqual(parsed.occurrences.map(\.surfaceText), ["office table"])
        XCTAssertEqual(parsed.occurrences.first?.range, NSRange(location: 12, length: 12))
        XCTAssertTrue(parsed.missingWords.isEmpty)
    }

    /// Markdown 粗体位于 vocab 标签内部时也要清理，避免模型标记顺序不同就污染阅读正文。
    func testArticleVocabularyMarkupParserRemovesMarkdownEmphasisInsideVocabularyMarker() {
        let word = VocabWord(id: "phrase-1", spelling: "office table")
        let parsed = ArticleVocabularyMarkupParser().parse(
            content: "Pass me the <vocab id=\"w1\">**office table**</vocab> clutter.",
            targetWords: [word],
            markerWordByID: ["w1": word]
        )

        XCTAssertEqual(parsed.content, "Pass me the office table clutter.")
        XCTAssertEqual(parsed.occurrences.map(\.surfaceText), ["office table"])
        XCTAssertEqual(parsed.occurrences.first?.range, NSRange(location: 12, length: 12))
        XCTAssertTrue(parsed.missingWords.isEmpty)
    }

    /// 阅读辅助动作在展开前后保持稳定短文案，只通过视觉选中态和辅助功能标签表达“收起”。
    func testReadingSupplementActionPresentationKeepsVisibleLabelsStableAcrossStates() {
        let inactive = ReadingSupplementActionPresentation(
            action: .translation,
            isActive: false,
            isLoading: false,
            isDisabled: false
        )
        let active = ReadingSupplementActionPresentation(
            action: .translation,
            isActive: true,
            isLoading: false,
            isDisabled: false
        )

        XCTAssertEqual(inactive.title, "翻译")
        XCTAssertEqual(active.title, "翻译")
        XCTAssertEqual(inactive.accessibilityLabel, "翻译")
        XCTAssertEqual(active.accessibilityLabel, "收起翻译")
    }

    /// 翻译和解析必须从共享语义模型取得固定图标，避免两个页面继续各自定义视觉语言。
    func testReadingSupplementActionsUseSharedIcons() {
        let translation = ReadingSupplementActionPresentation(
            action: .translation,
            isActive: false,
            isLoading: false,
            isDisabled: false
        )
        let analysis = ReadingSupplementActionPresentation(
            action: .analysis,
            isActive: false,
            isLoading: false,
            isDisabled: false
        )

        XCTAssertEqual(translation.systemImage, "character.book.closed")
        XCTAssertEqual(analysis.systemImage, "text.magnifyingglass")
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

    func testArticleContentFormatterHighlightsMarkedPhraseOccurrence() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "The plane took off after sunrise.",
            targetWords: [VocabWord(id: "phrase-1", spelling: "take off")],
            vocabularyOccurrences: [
                ArticleVocabularyOccurrence(
                    word: VocabWord(id: "phrase-1", spelling: "take off"),
                    surfaceText: "took off",
                    range: NSRange(location: 10, length: 8)
                )
            ]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(String(formatted.characters), article.content)
        XCTAssertEqual(linkedRuns.map(\.absoluteString), ["word://take%20off"])
    }

    /// 没有 LLM 标签时，本地兜底也要识别短语中的常见规则词形变化。
    func testArticleContentFormatterMatchesRegularInflectionsInsidePhraseTargets() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "They are growing hemp, and several items on the agenda cover safety.",
            targetWords: [
                VocabWord(id: "phrase-1", spelling: "grow hemp"),
                VocabWord(id: "phrase-2", spelling: "item on the agenda")
            ]
        )

        let formatted = ArticleContentFormatter().format(article: article)
        let linkedRuns = formatted.runs.compactMap(\.link)

        XCTAssertEqual(
            linkedRuns.map(\.absoluteString),
            ["word://grow%20hemp", "word://item%20on%20the%20agenda"]
        )
    }

    func testArticleParagraphExtractorCarriesMarkedOccurrencesIntoParagraphs() {
        let article = Article(
            id: UUID(),
            scene: .novel,
            content: "The plane took off after sunrise.\n\nThe river was quiet.",
            targetWords: [VocabWord(id: "phrase-1", spelling: "take off")],
            vocabularyOccurrences: [
                ArticleVocabularyOccurrence(
                    word: VocabWord(id: "phrase-1", spelling: "take off"),
                    surfaceText: "took off",
                    range: NSRange(location: 10, length: 8)
                )
            ]
        )

        let paragraphs = ArticleParagraphExtractor().extract(from: article)

        XCTAssertEqual(paragraphs.first?.vocabularyOccurrences.count, 1)
        XCTAssertEqual(paragraphs.first?.vocabularyOccurrences.first?.range, NSRange(location: 10, length: 8))
        XCTAssertTrue(paragraphs.dropFirst().allSatisfy { $0.vocabularyOccurrences.isEmpty })
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
