import Foundation
import os

protocol TodayArticlePagingSession: AnyObject {
    func hasMoreArticles() async throws -> Bool
    func loadNextArticle() async throws -> Article?
}

protocol TodayArticleGenerating {
    func generateTodayArticles() async throws -> [Article]
    func generateTodayArticlesStream() -> AsyncThrowingStream<Article, Error>
    func makePagingSession() -> TodayArticlePagingSession
    func makePagingSession(startingAtConsumedWordCount: Int) -> TodayArticlePagingSession
}

final class ArticleGenerator {
    fileprivate static let logger = Logger(subsystem: "com.vocabreader.app", category: "ArticleGenerator")

    private let maiMemo: MaiMemoServiceProtocol
    private let llm: LLMServiceProtocol
    private let batchSize: Int
    private let todayWordLimit: Int
    private let scenes: [ArticleScene]
    private let topic: ArticleTopic
    private let interBatchDelayNanoseconds: UInt64 = 350_000_000

    init(
        maiMemo: MaiMemoServiceProtocol,
        llm: LLMServiceProtocol,
        batchSize: Int = 10,
        todayWordLimit: Int = 50,
        scenes: [ArticleScene] = ArticleScene.allCases,
        topic: ArticleTopic = .general
    ) {
        self.maiMemo = maiMemo
        self.llm = llm
        self.batchSize = batchSize
        self.todayWordLimit = todayWordLimit
        self.scenes = Self.normalizedScenes(scenes)
        self.topic = topic
    }

    func makePagingSession() -> TodayArticlePagingSession {
        makePagingSession(startingAtConsumedWordCount: 0)
    }

    func makePagingSession(startingAtConsumedWordCount: Int) -> TodayArticlePagingSession {
        PagingSession(
            maiMemo: maiMemo,
            llm: llm,
            batchSize: batchSize,
            todayWordLimit: todayWordLimit,
            scenes: scenes,
            topic: topic,
            interBatchDelayNanoseconds: interBatchDelayNanoseconds,
            consumedWordCount: startingAtConsumedWordCount
        )
    }

    func generateTodayArticles() async throws -> [Article] {
        var articles: [Article] = []
        let session = makePagingSession()

        while let article = try await session.loadNextArticle() {
            articles.append(article)
        }

        return sortArticles(articles)
    }

    func generateTodayArticlesStream() -> AsyncThrowingStream<Article, Error> {
        let session = makePagingSession()
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    while let article = try await session.loadNextArticle() {
                        continuation.yield(article)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func sortArticles(_ articles: [Article]) -> [Article] {
        articles.sorted { a, b in
            guard let firstA = a.targetWords.first, let firstB = b.targetWords.first else { return false }
            return firstA.spelling < firstB.spelling
        }
    }

    /// 规范化体裁列表，避免设置层传入空数组导致轮转崩溃。
    private static func normalizedScenes(_ scenes: [ArticleScene]) -> [ArticleScene] {
        let normalizedScenes = ArticleScene.allCases.filter { scenes.contains($0) }
        return normalizedScenes.isEmpty ? ArticleScene.allCases : normalizedScenes
    }
}

extension ArticleGenerator: TodayArticleGenerating {}

private final class PagingSession: TodayArticlePagingSession {
    private let maiMemo: MaiMemoServiceProtocol
    private let llm: LLMServiceProtocol
    private let batchSize: Int
    private let todayWordLimit: Int
    private let interBatchDelayNanoseconds: UInt64
    private let scenes: [ArticleScene]
    private let topic: ArticleTopic
    private let consumedWordCount: Int

    private var batches: [[VocabWord]]?
    private var nextBatchIndex = 0

    init(
        maiMemo: MaiMemoServiceProtocol,
        llm: LLMServiceProtocol,
        batchSize: Int,
        todayWordLimit: Int,
        scenes: [ArticleScene],
        topic: ArticleTopic,
        interBatchDelayNanoseconds: UInt64,
        consumedWordCount: Int
    ) {
        self.maiMemo = maiMemo
        self.llm = llm
        self.batchSize = batchSize
        self.todayWordLimit = todayWordLimit
        self.scenes = scenes
        self.topic = topic
        self.interBatchDelayNanoseconds = interBatchDelayNanoseconds
        self.consumedWordCount = consumedWordCount
    }

    func hasMoreArticles() async throws -> Bool {
        let batches = try await resolveBatches()
        return nextBatchIndex < batches.count
    }

    func loadNextArticle() async throws -> Article? {
        let batches = try await resolveBatches()
        guard nextBatchIndex < batches.count else { return nil }

        if nextBatchIndex > 0 {
            try await Task.sleep(nanoseconds: interBatchDelayNanoseconds)
        }

        let batch = batches[nextBatchIndex]
        let scene = scenes[nextBatchIndex % scenes.count]
        ArticleGenerator.logger.info(
            "Generating batch \(self.nextBatchIndex + 1, privacy: .public)/\(batches.count, privacy: .public) with \(batch.count, privacy: .public) words"
        )

        nextBatchIndex += 1
        return try await llm.generateArticle(words: batch, scene: scene, topic: topic)
    }

    private func resolveBatches() async throws -> [[VocabWord]] {
        if let batches {
            return batches
        }

        let words = try await maiMemo.fetchTodayWords(limit: todayWordLimit)
        let startIndex = min(max(consumedWordCount, 0), words.count)
        let remainingWords = Array(words.dropFirst(startIndex))
        let batches = stride(from: 0, to: remainingWords.count, by: batchSize).map {
            Array(remainingWords[$0..<min($0 + batchSize, remainingWords.count)])
        }
        self.batches = batches
        return batches
    }
}
