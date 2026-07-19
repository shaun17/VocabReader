import XCTest
@testable import VocabReader

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testLoadArticlesLoadsInitialBatch() async {
        let articles = (1...5).map { i in
            Article(
                id: UUID(),
                scene: .novel,
                content: "article\(i)",
                targetWords: [VocabWord(id: "\(i)", spelling: "word\(i)")]
            )
        }
        let viewModel = TodayViewModel {
            MockTodayArticleGenerator(articles: articles)
        }

        await viewModel.loadArticles()
        XCTAssertEqual(viewModel.articles.map(\.content), ["article1", "article2", "article3"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testCoveredWordCountSumsGeneratedArticleTargets() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .dialogue,
            content: "first",
            targetWords: [
                VocabWord(id: "1", spelling: "pistol"),
                VocabWord(id: "2", spelling: "humble"),
                VocabWord(id: "3", spelling: "chop")
            ]
        )
        let secondArticle = Article(
            id: UUID(),
            scene: .science,
            content: "second",
            targetWords: [
                VocabWord(id: "4", spelling: "keen"),
                VocabWord(id: "5", spelling: "remedy"),
                VocabWord(id: "6", spelling: "petrol"),
                VocabWord(id: "7", spelling: "recourse")
            ]
        )
        let viewModel = TodayViewModel {
            MockTodayArticleGenerator(articles: [firstArticle, secondArticle])
        }

        await viewModel.loadArticles()

        XCTAssertEqual(viewModel.coveredWordCount, 7)
    }

    func testLoadMoreRequiresListInteraction() async {
        let articles = (1...5).map { i in
            Article(
                id: UUID(),
                scene: .novel,
                content: "article\(i)",
                targetWords: [VocabWord(id: "\(i)", spelling: "word\(i)")]
            )
        }
        let viewModel = TodayViewModel {
            MockTodayArticleGenerator(articles: articles)
        }

        await viewModel.loadArticles()
        await viewModel.loadMoreIfNeededForListTail()

        // Without setting footer visible, no additional loading happens
        XCTAssertEqual(viewModel.articles.map(\.content), ["article1", "article2", "article3"])
        XCTAssertNil(viewModel.error)
    }

    func testLoadMoreAppendsNextArticleAfterFooterBecomesVisible() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .novel,
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
            scene: .novel,
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
        let fourthArticle = Article(
            id: UUID(),
            scene: .novel,
            content: "fourth",
            targetWords: [VocabWord(id: "4", spelling: "cloud")]
        )
        let pagingSession = ControlledPagingSession(
            articles: [firstArticle, secondArticle, thirdArticle, fourthArticle],
            blockedLoadCall: 4
        )
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
        XCTAssertEqual(totalCalls, 4)
        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third", "fourth"])
    }

    func testSaveSettingsUpdatesPaginationWhenTotalWordCountIncreasesWithoutReload() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .novel,
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

        await viewModel.syncPaginationSettingsAfterSave(
            previousSettings: ArticleGenerationSettings(articleWordCount: 20, wordsPerArticle: 10),
            newSettings: ArticleGenerationSettings(articleWordCount: 30, wordsPerArticle: 10)
        )

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second"])
        XCTAssertTrue(viewModel.shouldShowLoadMoreFooter)

        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third"])
        XCTAssertEqual(factory.makeCount, 2)
    }

    func testSaveSettingsUpdatesPaginationWhenWordsPerArticleChangesWithoutReload() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .novel,
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

        await viewModel.syncPaginationSettingsAfterSave(
            previousSettings: ArticleGenerationSettings(articleWordCount: 20, wordsPerArticle: 10),
            newSettings: ArticleGenerationSettings(articleWordCount: 25, wordsPerArticle: 5)
        )

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second"])
        XCTAssertTrue(viewModel.shouldShowLoadMoreFooter)

        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third"])
        XCTAssertEqual(factory.makeCount, 2)
    }

    func testSaveSettingsUpdatesSessionWhenTopicChanges() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .novel,
            topic: .general,
            content: "first",
            targetWords: [VocabWord(id: "1", spelling: "apple")]
        )
        let replacementArticle = Article(
            id: UUID(),
            scene: .science,
            topic: .medical,
            content: "replacement",
            targetWords: [VocabWord(id: "3", spelling: "clinic")]
        )
        let factory = MockTodayArticleGeneratorFactory(generators: [
            MockTodayArticleGenerator(articles: [firstArticle]),
            MockTodayArticleGenerator(articles: [replacementArticle])
        ])
        let viewModel = TodayViewModel {
            factory.makeGenerator()
        }

        await viewModel.loadArticles()

        await viewModel.syncPaginationSettingsAfterSave(
            previousSettings: ArticleGenerationSettings(
                articleWordCount: 20,
                wordsPerArticle: 10,
                selectedTopic: .general,
                enabledScenes: [.dialogue, .science, .novel]
            ),
            newSettings: ArticleGenerationSettings(
                articleWordCount: 30,
                wordsPerArticle: 10,
                selectedTopic: .medical,
                enabledScenes: [.dialogue, .science, .novel]
            )
        )

        // Topic changed — should NOT trigger reload, only update session
        XCTAssertEqual(viewModel.articles.map(\.content), ["first"])
        // New generator created for future pagination
        XCTAssertEqual(factory.makeCount, 2)
    }

    func testRegenerateArticlesForcesRefresh() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .novel,
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

    func testLoadMoreCanRetryAfterTransientNetworkFailure() async {
        let firstArticle = Article(
            id: UUID(),
            scene: .novel,
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
        let fourthArticle = Article(
            id: UUID(),
            scene: .novel,
            content: "fourth",
            targetWords: [VocabWord(id: "4", spelling: "cloud")]
        )
        let pagingSession = TransientLoadMoreFailurePagingSession(
            initialArticles: [firstArticle, secondArticle, thirdArticle],
            retryArticle: fourthArticle
        )
        let viewModel = TodayViewModel {
            FixedPagingGenerator(session: pagingSession)
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third"])
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.shouldShowLoadMoreFooter)

        await viewModel.loadMoreIfNeededForListTail()

        XCTAssertEqual(viewModel.articles.map(\.content), ["first", "second", "third", "fourth"])
        XCTAssertNil(viewModel.error)
    }

    /// 用户重试加载时应立即清掉旧错误，不能在新请求进行中同时显示“生成失败”和加载动画。
    func testLoadMoreClearsPreviousErrorBeforeRetryFinishes() async {
        let initialArticles = (1...3).map { index in
            Article(
                id: UUID(),
                scene: .novel,
                content: "article\(index)",
                targetWords: [VocabWord(id: "\(index)", spelling: "word\(index)")]
            )
        }
        let retryArticle = Article(
            id: UUID(),
            scene: .science,
            content: "retried",
            targetWords: [VocabWord(id: "4", spelling: "word4")]
        )
        let pagingSession = BlockingRetryPagingSession(
            initialArticles: initialArticles,
            retryArticle: retryArticle
        )
        let viewModel = TodayViewModel {
            FixedPagingGenerator(session: pagingSession)
        }

        await viewModel.loadArticles()
        viewModel.setLoadMoreFooterVisible(true)
        await viewModel.loadMoreIfNeededForListTail()
        XCTAssertNotNil(viewModel.error)

        let retryTask = Task {
            await viewModel.loadMoreIfNeededForListTail()
        }
        await pagingSession.waitUntilRetryStarts()

        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.isLoadingMore)

        await pagingSession.resumeRetry()
        await retryTask.value
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

private actor TransientLoadMoreFailurePagingSession: TodayArticlePagingSession {
    private var initialArticles: [Article]
    private let retryArticle: Article
    private var didFailLoadMore = false
    private var didReturnRetryArticle = false

    init(initialArticles: [Article], retryArticle: Article) {
        self.initialArticles = initialArticles
        self.retryArticle = retryArticle
    }

    func hasMoreArticles() async throws -> Bool {
        !initialArticles.isEmpty || !didReturnRetryArticle
    }

    func loadNextArticle() async throws -> Article? {
        if !initialArticles.isEmpty {
            return initialArticles.removeFirst()
        }

        if !didFailLoadMore {
            didFailLoadMore = true
            throw TodayViewModelTestError.transientNetwork
        }

        guard !didReturnRetryArticle else { return nil }
        didReturnRetryArticle = true
        return retryArticle
    }
}

/// 第一次加载更多失败、第二次阻塞到测试放行，用来观察重试进行中的页面状态。
private actor BlockingRetryPagingSession: TodayArticlePagingSession {
    private var initialArticles: [Article]
    private let retryArticle: Article
    private var didFailLoadMore = false
    private var didReturnRetryArticle = false
    private var retryStarted = false
    private var retryStartedContinuation: CheckedContinuation<Void, Never>?
    private var retryResumeContinuation: CheckedContinuation<Void, Never>?

    init(initialArticles: [Article], retryArticle: Article) {
        self.initialArticles = initialArticles
        self.retryArticle = retryArticle
    }

    /// 只要初始文章或重试文章尚未返回，分页就仍可继续。
    func hasMoreArticles() async throws -> Bool {
        !initialArticles.isEmpty || !didReturnRetryArticle
    }

    /// 初始三篇正常返回，第四次抛错，第五次等待测试检查 UI 状态后再成功。
    func loadNextArticle() async throws -> Article? {
        if !initialArticles.isEmpty {
            return initialArticles.removeFirst()
        }

        if !didFailLoadMore {
            didFailLoadMore = true
            throw TodayViewModelTestError.transientNetwork
        }

        guard !didReturnRetryArticle else { return nil }
        retryStarted = true
        retryStartedContinuation?.resume()
        retryStartedContinuation = nil
        await withCheckedContinuation { continuation in
            retryResumeContinuation = continuation
        }
        didReturnRetryArticle = true
        return retryArticle
    }

    /// 等待第二次加载更多真正进入阻塞点，避免测试和异步请求竞态。
    func waitUntilRetryStarts() async {
        guard !retryStarted else { return }
        await withCheckedContinuation { continuation in
            retryStartedContinuation = continuation
        }
    }

    /// 放行被阻塞的重试请求，使测试能够正常收尾。
    func resumeRetry() {
        retryResumeContinuation?.resume()
        retryResumeContinuation = nil
    }
}

private enum TodayViewModelTestError: LocalizedError {
    case transientNetwork

    var errorDescription: String? {
        "临时网络异常"
    }
}
