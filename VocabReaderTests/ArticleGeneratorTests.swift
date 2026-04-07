import XCTest
@testable import VocabReader

final class ArticleGeneratorTests: XCTestCase {

    func testGroupsWordsInto20() async throws {
        var capturedBatches: [[VocabWord]] = []
        let mockLLM = MockLLMService { words, scene in
            capturedBatches.append(words)
            return Article(id: UUID(), scene: scene, content: "text", targetWords: words)
        }
        let words = (1...45).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let mockMaiMemo = MockMaiMemoService(words: words)
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)

        _ = try await generator.generateTodayArticles()

        let sortedCounts = capturedBatches.map { $0.count }.sorted()
        XCTAssertEqual(sortedCounts, [5, 20, 20])
    }

    func testReturnsEmptyWhenNoWords() async throws {
        let mockLLM = MockLLMService { words, scene in
            Article(id: UUID(), scene: scene, content: "", targetWords: words)
        }
        let mockMaiMemo = MockMaiMemoService(words: [])
        let generator = ArticleGenerator(maiMemo: mockMaiMemo, llm: mockLLM)

        let articles = try await generator.generateTodayArticles()

        XCTAssertTrue(articles.isEmpty)
    }
}

// MARK: - Mocks

final class MockMaiMemoService: MaiMemoServiceProtocol {
    let words: [VocabWord]
    init(words: [VocabWord]) { self.words = words }
    func fetchTodayWords(limit: Int) async throws -> [VocabWord] { words }
    func fetchDefinition(vocId: String) async throws -> String? { "definition" }
}

final class MockLLMService: LLMServiceProtocol {
    let handler: ([VocabWord], ArticleScene) async throws -> Article
    init(_ handler: @escaping ([VocabWord], ArticleScene) async throws -> Article) {
        self.handler = handler
    }
    func generateArticle(words: [VocabWord], scene: ArticleScene) async throws -> Article {
        try await handler(words, scene)
    }
}
