import XCTest
@testable import VocabReader

final class ArticleGeneratorTests: XCTestCase {
    func testUsesConfiguredTodayWordLimit() async throws {
        let mockLLM = MockLLMService { words, scene, topic in
            Article(id: UUID(), scene: scene, topic: topic, content: "text", targetWords: words)
        }
        let mockMaiMemo = MockMaiMemoService(words: [])
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM, todayWordLimit: 30)

        _ = try await generator.generateTodayArticles()

        XCTAssertEqual(mockMaiMemo.lastRequestedLimit, 30)
    }

    func testGroupsWordsUsingConfiguredWordsPerArticle() async throws {
        let collector = BatchCollector()
        let mockLLM = MockLLMService { words, scene, topic in
            await collector.append(words)
            return Article(id: UUID(), scene: scene, topic: topic, content: "text", targetWords: words)
        }
        let words = (1...45).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM, batchSize: 15)

        _ = try await generator.generateTodayArticles()

        let capturedBatches = await collector.batches
        let sortedCounts = capturedBatches.map { $0.count }.sorted()
        XCTAssertEqual(sortedCounts, [15, 15, 15])
    }

    func testReturnsEmptyWhenNoWords() async throws {
        let mockLLM = MockLLMService { words, scene, topic in
            Article(id: UUID(), scene: scene, topic: topic, content: "", targetWords: words)
        }
        let mockMaiMemo = MockMaiMemoService(words: [])
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)

        let articles = try await generator.generateTodayArticles()

        XCTAssertTrue(articles.isEmpty)
    }

    func testGeneratesArticlesOneBatchAtATime() async throws {
        let tracker = ConcurrentCallTracker()
        let mockLLM = MockLLMService { words, scene, topic in
            try await tracker.track {
                try await Task.sleep(nanoseconds: 50_000_000)
                return Article(id: UUID(), scene: scene, topic: topic, content: "text", targetWords: words)
            }
        }
        let words = (1...50).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)

        _ = try await generator.generateTodayArticles()

        let maxConcurrentCalls = await tracker.maxConcurrentCalls
        XCTAssertEqual(maxConcurrentCalls, 1)
    }

    func testGenerateTodayArticlesStreamYieldsBeforeAllBatchesFinish() async throws {
        let firstArticleDelivered = XCTestExpectation(description: "first article delivered")
        let mockLLM = MockLLMService { words, scene, topic in
            if words.first?.spelling == "word11" {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            return Article(id: UUID(), scene: scene, topic: topic, content: words.map(\.spelling).joined(separator: ","), targetWords: words)
        }
        let words = (1...20).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)

        let startedAt = Date()
        let stream = generator.generateTodayArticlesStream()
        var iterator = stream.makeAsyncIterator()

        let firstArticle = try await iterator.next()
        XCTAssertNotNil(firstArticle)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.45)
        firstArticleDelivered.fulfill()
    }

    func testPagingSessionLoadsOneBatchPerRequest() async throws {
        let collector = BatchCollector()
        let mockLLM = MockLLMService { words, scene, topic in
            await collector.append(words)
            return Article(id: UUID(), scene: scene, topic: topic, content: "text", targetWords: words)
        }
        let words = (1...20).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)
        let session = generator.makePagingSession()

        let firstArticle = try await session.loadNextArticle()
        let batchCountAfterFirstLoad = await collector.batches.count

        XCTAssertNotNil(firstArticle)
        XCTAssertEqual(batchCountAfterFirstLoad, 1)

        let secondArticle = try await session.loadNextArticle()
        let batchCountAfterSecondLoad = await collector.batches.count

        XCTAssertNotNil(secondArticle)
        XCTAssertEqual(batchCountAfterSecondLoad, 2)
    }

    func testPagingSessionReturnsNilAfterLastBatch() async throws {
        let mockLLM = MockLLMService { words, scene, topic in
            Article(id: UUID(), scene: scene, topic: topic, content: "text", targetWords: words)
        }
        let words = (1...10).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)
        let session = generator.makePagingSession()

        _ = try await session.loadNextArticle()
        let nextArticle = try await session.loadNextArticle()

        XCTAssertNil(nextArticle)
    }

    func testUsesConfiguredScenesAndTopicWhenGeneratingArticles() async throws {
        let recorder = GenerationRecorder()
        let mockLLM = MockLLMService { words, scene, topic in
            await recorder.record(scene: scene, topic: topic)
            return Article(id: UUID(), scene: scene, topic: topic, content: "text", targetWords: words)
        }
        let words = (1...20).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(
            maiMemo: mockMaiMemo,
            llm: mockLLM,
            batchSize: 10,
            scenes: [.dialogue, .science],
            topic: .ai
        )

        _ = try await generator.generateTodayArticles()

        let generatedScenes = await recorder.scenes
        let generatedTopics = await recorder.topics
        XCTAssertEqual(generatedScenes, [.dialogue, .science])
        XCTAssertEqual(generatedTopics, [.ai, .ai])
    }
}

actor BatchCollector {
    private(set) var batches: [[VocabWord]] = []

    func append(_ words: [VocabWord]) {
        batches.append(words)
    }
}

actor ConcurrentCallTracker {
    private(set) var maxConcurrentCalls = 0
    private var activeCalls = 0

    func track<T>(_ operation: () async throws -> T) async rethrows -> T {
        activeCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
        defer { activeCalls -= 1 }
        return try await operation()
    }
}

actor GenerationRecorder {
    private(set) var scenes: [ArticleScene] = []
    private(set) var topics: [ArticleTopic] = []

    func record(scene: ArticleScene, topic: ArticleTopic) {
        scenes.append(scene)
        topics.append(topic)
    }
}

// MARK: - Mocks

final class MockMaiMemoService: MaiMemoServiceProtocol {
    let words: [VocabWord]
    private(set) var lastRequestedLimit: Int?

    init(words: [VocabWord]) { self.words = words }

    func fetchTodayWords(limit: Int) async throws -> [VocabWord] {
        lastRequestedLimit = limit
        return words
    }

    func fetchDefinition(vocId: String) async throws -> String? { "definition" }
}

final class MockLLMService: LLMServiceProtocol {
    let handler: ([VocabWord], ArticleScene, ArticleTopic) async throws -> Article
    init(_ handler: @escaping ([VocabWord], ArticleScene, ArticleTopic) async throws -> Article) {
        self.handler = handler
    }
    func generateArticle(words: [VocabWord], scene: ArticleScene, topic: ArticleTopic) async throws -> Article {
        try await handler(words, scene, topic)
    }
}
