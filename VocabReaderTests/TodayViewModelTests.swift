import XCTest
@testable import VocabReader

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testLoadArticlesLoadsOnlyFirstArticle() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let viewModel = TodayViewModel {
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle])
        }

        await viewModel.loadArticles()
        XCTAssertEqual(viewModel.articles.map(\.content), ["first"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadMoreRequiresListInteraction() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let viewModel = TodayViewModel {
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle])
        }

        await viewModel.loadArticles()
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first"])
        XCTAssertNil(viewModel.error)
    }

    func testLoadMoreAppendsNextArticleAfterFooterBecomesVisible() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let viewModel = TodayViewModel {
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle])
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second"])
        XCTAssertNil(viewModel.error)
    }

    func testRepeatedLoadMoreWhileRequestIsInFlightTriggersOnlyOneAdditionalRequest() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let pagingSession = ControlledPagingSession(articles: [firstArticle, secondArticle], blockedLoadCall: 2)
        let viewModel = TodayViewModel {
            FixedPagingGenerator(session: pagingSession)
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)

        let firstLoadMore = Task {
            await viewModel.loadMoreIfNeededForListTail()
        }

        await pagingSession.waitUntilBlockedLoadStarts()
        await viewModel.loadMoreIfNeededForListTail()
        await pagingSession.resumeBlockedLoad()
        await firstLoadMore.value

        let totalCalls = await pagingSession.loadNextArticleCallCount
        XCTAssertEqual(totalCalls, 2)
        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second"])
    }

    func testSaveSettingsLoadsArticlesOnlyWhenHomeIsEmpty() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let replacementArticle = Article(
            id: UUID(),
            scene: .science,
            content: "replacement",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let factory = MockTodayArticleGeneratorFactory(generators: [
            MockTodayArticleGenerator(articles: [firstArticle]),
            MockTodayArticleGenerator(articles: [replacementArticle])
        ])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.loadArticles()
        await viewModel.reloadIfNeededAfterSettingsSave()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first"])
        XCTAssertEqual(factory.makeCount, 1)
    }

    func testSaveSettingsLoadsArticlesWhenHomeIsEmpty() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let factory = MockTodayArticleGeneratorFactory(generators: [
            MockTodayArticleGenerator(articles: [firstArticle])
        ])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.reloadIfNeededAfterSettingsSave()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first"])
        XCTAssertEqual(factory.makeCount, 1)
    }

    func testSaveSettingsExtendsPaginationWhenTotalWordCountIncreases() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let thirdArticle = Article(
            id: UUID(),
            scene: .dialogue,
            content: "third",
            targetWords: [VocabWord(id: "3", spelling: "river")]
        )
        let factory = MockTodayArticleGeneratorFactory(generators: [
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle]),
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle, thirdArticle])
        ])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertFalse(viewModel.shouldShowLoadMoreFooter)

        await viewModel.applySettingsAfterSave(
            previousSettings: ArticleGenerationSettings(articleWordCount: 20, wordsPerArticle: 10),
            newSettings: ArticleGenerationSettings(articleWordCount: 30, wordsPerArticle: 10)
        )

        XCTAssertTrue(viewModel.shouldShowLoadMoreFooter)

        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third"])
        XCTAssertEqual(factory.makeCount, 2)
    }

    func testSaveSettingsExtendsPaginationWhenWordsPerArticleChanges() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [
                VocabWord(id: "1", spelling: "word1"),
                VocabWord(id: "2", spelling: "word2"),
                VocabWord(id: "3", spelling: "word3"),
                VocabWord(id: "4", spelling: "word4"),
                VocabWord(id: "5", spelling: "word5"),
                VocabWord(id: "6", spelling: "word6"),
                VocabWord(id: "7", spelling: "word7"),
                VocabWord(id: "8", spelling: "word8"),
                VocabWord(id: "9", spelling: "word9"),
                VocabWord(id: "10", spelling: "word10")
            ]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [
                VocabWord(id: "11", spelling: "word11"),
                VocabWord(id: "12", spelling: "word12"),
                VocabWord(id: "13", spelling: "word13"),
                VocabWord(id: "14", spelling: "word14"),
                VocabWord(id: "15", spelling: "word15"),
                VocabWord(id: "16", spelling: "word16"),
                VocabWord(id: "17", spelling: "word17"),
                VocabWord(id: "18", spelling: "word18"),
                VocabWord(id: "19", spelling: "word19"),
                VocabWord(id: "20", spelling: "word20")
            ]
        )
        let thirdArticle = Article(
            id: UUID(),
            scene: .dialogue,
            content: "third",
            targetWords: [
                VocabWord(id: "21", spelling: "word21"),
                VocabWord(id: "22", spelling: "word22"),
                VocabWord(id: "23", spelling: "word23"),
                VocabWord(id: "24", spelling: "word24"),
                VocabWord(id: "25", spelling: "word25")
            ]
        )
        let factory = MockTodayArticleGeneratorFactory(generators: [
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle]),
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle, thirdArticle])
        ])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertFalse(viewModel.shouldShowLoadMoreFooter)

        await viewModel.applySettingsAfterSave(
            previousSettings: ArticleGenerationSettings(articleWordCount: 20, wordsPerArticle: 10),
            newSettings: ArticleGenerationSettings(articleWordCount: 25, wordsPerArticle: 5)
        )

        XCTAssertTrue(viewModel.shouldShowLoadMoreFooter)

        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third"])
        XCTAssertEqual(factory.makeCount, 2)
    }

    func testIncreasingTodayWordCountRestoresLoadMoreWithoutSessionPreflight() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let thirdArticle = Article(
            id: UUID(),
            scene: .dialogue,
            content: "third",
            targetWords: [VocabWord(id: "3", spelling: "river")]
        )
        let initialSession = MockTodayArticlePagingSession(articles: [firstArticle, secondArticle])
        let resumedSession = ThrowingHasMorePagingSession(articles: [thirdArticle])
        let factory = SequentialPagingGeneratorFactory(sessions: [initialSession, resumedSession])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertFalse(viewModel.shouldShowLoadMoreFooter)

        await viewModel.applySettingsAfterSave(
            previousSettings: ArticleGenerationSettings(articleWordCount: 20, wordsPerArticle: 10),
            newSettings: ArticleGenerationSettings(articleWordCount: 30, wordsPerArticle: 10)
        )

        XCTAssertTrue(viewModel.shouldShowLoadMoreFooter)

        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third"])
    }

    func testRegenerateArticlesForcesRefresh() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .story,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let regeneratedArticle = Article(
            id: UUID(),
            scene: .science,
            content: "regenerated",
            targetWords: [VocabWord(id: "2", spelling: "banana")]
        )
        let factory = MockTodayArticleGeneratorFactory(generators: [
            MockTodayArticleGenerator(articles: [firstArticle]),
            MockTodayArticleGenerator(articles: [regeneratedArticle])
        ])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.loadArticles()
        await viewModel.regenerateArticles()

        XCTAssertEqual(viewModel.articles.map(\.content), ["regenerated"])
        XCTAssertEqual(factory.makeCount, 2)
    }
}

@MainActor
private final class MockTodayArticleGeneratorFactory {
    private let generators: [TodayArticleGenerating]
    private(set) var makeCount = 0

    init(generators: [TodayArticleGenerating]) {
        self.generators = generators
    }

    func makeGenerator() -> TodayArticleGenerating {
        let index = min(makeCount, generators.count - 1)
        makeCount += 1
        return generators[index]
    }
}

private final class MockTodayArticleGenerator: TodayArticleGenerating {
    private let articles: [Article]

    init(articles: [Article]) {
        self.articles = articles
    }

    func generateTodayArticles() async throws -> [Article] {
        articles
    }

    func generateTodayArticlesStream() -> AsyncThrowingStream<Article, Error> {
        let articles = self.articles
        return AsyncThrowingStream { continuation in
            Task {
                for article in articles {
                    continuation.yield(article)
                }
                continuation.finish()
            }
        }
    }

    func makePagingSession() -> TodayArticlePagingSession {
        makePagingSession(startingAtConsumedWordCount: 0)
    }

    func makePagingSession(startingAtConsumedWordCount: Int) -> TodayArticlePagingSession {
        MockTodayArticlePagingSession(
            articles: dropConsumedArticles(startingAtConsumedWordCount)
        )
    }

    private func dropConsumedArticles(_ consumedWordCount: Int) -> [Article] {
        var remainingWordCount = consumedWordCount
        var remainingArticles = articles

        while let firstArticle = remainingArticles.first, remainingWordCount > 0 {
            remainingWordCount -= firstArticle.targetWords.count
            remainingArticles.removeFirst()
        }

        return remainingArticles
    }
}

private final class MockTodayArticlePagingSession: TodayArticlePagingSession {
    private var remainingArticles: [Article]

    init(articles: [Article]) {
        self.remainingArticles = articles
    }

    func hasMoreArticles() async throws -> Bool {
        !remainingArticles.isEmpty
    }

    func loadNextArticle() async throws -> Article? {
        guard !remainingArticles.isEmpty else { return nil }
        return remainingArticles.removeFirst()
    }
}

private final class ThrowingHasMorePagingSession: TodayArticlePagingSession {
    private var remainingArticles: [Article]

    init(articles: [Article]) {
        self.remainingArticles = articles
    }

    func hasMoreArticles() async throws -> Bool {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "preflight failed"])
    }

    func loadNextArticle() async throws -> Article? {
        guard !remainingArticles.isEmpty else { return nil }
        return remainingArticles.removeFirst()
    }
}

@MainActor
private final class SequentialPagingGeneratorFactory {
    private let sessions: [TodayArticlePagingSession]
    private var nextIndex = 0

    init(sessions: [TodayArticlePagingSession]) {
        self.sessions = sessions
    }

    func makeGenerator() -> TodayArticleGenerating {
        let index = min(nextIndex, sessions.count - 1)
        nextIndex += 1
        return FixedPagingGenerator(session: sessions[index])
    }
}

private final class FixedPagingGenerator: TodayArticleGenerating {
    private let session: TodayArticlePagingSession

    init(session: TodayArticlePagingSession) {
        self.session = session
    }

    func generateTodayArticles() async throws -> [Article] {
        []
    }

    func generateTodayArticlesStream() -> AsyncThrowingStream<Article, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func makePagingSession() -> TodayArticlePagingSession {
        session
    }

    func makePagingSession(startingAtConsumedWordCount: Int) -> TodayArticlePagingSession {
        session
    }
}

private actor ControlledPagingSession: TodayArticlePagingSession {
    private var remainingArticles: [Article]
    private let blockedLoadCall: Int
    private var startedBlockedLoadContinuation: CheckedContinuation<Void, Never>?
    private var resumeBlockedLoadContinuation: CheckedContinuation<Void, Never>?

    private(set) var loadNextArticleCallCount = 0

    init(articles: [Article], blockedLoadCall: Int) {
        self.remainingArticles = articles
        self.blockedLoadCall = blockedLoadCall
    }

    func hasMoreArticles() async throws -> Bool {
        !remainingArticles.isEmpty
    }

    func loadNextArticle() async throws -> Article? {
        loadNextArticleCallCount += 1

        if loadNextArticleCallCount == blockedLoadCall {
            startedBlockedLoadContinuation?.resume()
            startedBlockedLoadContinuation = nil
            await withCheckedContinuation { continuation in
                resumeBlockedLoadContinuation = continuation
            }
        }

        guard !remainingArticles.isEmpty else { return nil }
        return remainingArticles.removeFirst()
    }

    func waitUntilBlockedLoadStarts() async {
        if loadNextArticleCallCount >= blockedLoadCall {
            return
        }

        await withCheckedContinuation { continuation in
            startedBlockedLoadContinuation = continuation
        }
    }

    func resumeBlockedLoad() {
        resumeBlockedLoadContinuation?.resume()
        resumeBlockedLoadContinuation = nil
    }
}
