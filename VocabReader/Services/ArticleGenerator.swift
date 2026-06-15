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

        // 只有完整原始批次成功生成后才推进索引；内部拆分不能改变"每篇词汇量"设置的语义。
        let article = try await generateArticlePreservingBatch(words: batch, scene: scene, topic: topic)
        nextBatchIndex += 1
        return article
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

    /// 保持外层批次不变；当模型无法一次覆盖全部目标词时，在同一篇文章内部递归拆分生成。
    private func generateArticlePreservingBatch(
        words: [VocabWord],
        scene: ArticleScene,
        topic: ArticleTopic
    ) async throws -> Article {
        do {
            return try await llm.generateArticle(words: words, scene: scene, topic: topic)
        } catch LLMError.missingVocabularyWords where words.count > 1 {
            return try await composeArticleFromSmallerBatches(words: words, scene: scene, topic: topic)
        } catch LLMError.requestTimedOut where words.count > 1 {
            return try await composeArticleFromSmallerBatches(words: words, scene: scene, topic: topic)
        }
    }

    /// 把失败的大批次拆成两个内部片段生成，并合并成一篇文章返回给阅读列表。
    private func composeArticleFromSmallerBatches(
        words: [VocabWord],
        scene: ArticleScene,
        topic: ArticleTopic
    ) async throws -> Article {
        let splitIndex = max(1, words.count / 2)
        let firstHalf = Array(words[..<splitIndex])
        let secondHalf = Array(words[splitIndex...])

        ArticleGenerator.logger.info(
            "Composing one article by splitting \(words.count, privacy: .public) words into \(firstHalf.count, privacy: .public) and \(secondHalf.count, privacy: .public)"
        )

        let firstArticle = try await generateArticlePreservingBatch(words: firstHalf, scene: scene, topic: topic)
        let secondArticle = try await generateArticlePreservingBatch(words: secondHalf, scene: scene, topic: topic)
        return composeArticle(
            from: [firstArticle, secondArticle],
            targetWords: words,
            scene: scene,
            topic: topic
        )
    }

    /// 合并内部片段正文，并把每个片段里的词汇命中范围平移到合并后的正文坐标。
    private func composeArticle(
        from articles: [Article],
        targetWords: [VocabWord],
        scene: ArticleScene,
        topic: ArticleTopic
    ) -> Article {
        var content = ""
        var occurrences: [ArticleVocabularyOccurrence] = []
        var currentLocation = 0

        for article in articles {
            let block = article.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !block.isEmpty else { continue }

            let rawContent = article.content as NSString
            let blockRangeInRaw = rawContent.range(of: block)
            let blockOffset = blockRangeInRaw.location == NSNotFound ? 0 : blockRangeInRaw.location

            if !content.isEmpty {
                content += "\n\n"
                currentLocation += 2
            }

            occurrences.append(contentsOf: shiftedOccurrences(
                article.vocabularyOccurrences,
                blockOffset: blockOffset,
                blockLength: (block as NSString).length,
                mergedOffset: currentLocation
            ))
            content += block
            currentLocation += (block as NSString).length
        }

        return Article(
            id: UUID(),
            scene: scene,
            topic: topic,
            content: content,
            targetWords: targetWords,
            vocabularyOccurrences: occurrences
        )
    }

    /// 只保留落在片段正文里的命中项，避免被裁掉的首尾空白影响高亮位置。
    private func shiftedOccurrences(
        _ occurrences: [ArticleVocabularyOccurrence],
        blockOffset: Int,
        blockLength: Int,
        mergedOffset: Int
    ) -> [ArticleVocabularyOccurrence] {
        occurrences.compactMap { occurrence in
            let occurrenceEnd = occurrence.range.location + occurrence.range.length
            let blockEnd = blockOffset + blockLength
            guard occurrence.range.location >= blockOffset, occurrenceEnd <= blockEnd else {
                return nil
            }

            return ArticleVocabularyOccurrence(
                word: occurrence.word,
                surfaceText: occurrence.surfaceText,
                range: NSRange(
                    location: mergedOffset + occurrence.range.location - blockOffset,
                    length: occurrence.range.length
                )
            )
        }
    }
}
