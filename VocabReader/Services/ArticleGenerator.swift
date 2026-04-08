import Foundation

final class ArticleGenerator {
    private let maiMemo: MaiMemoServiceProtocol
    private let llm: LLMServiceProtocol
    private let batchSize = 20
    private let todayWordLimit = 50

    init(maiMemo: MaiMemoServiceProtocol, llm: LLMServiceProtocol) {
        self.maiMemo = maiMemo
        self.llm = llm
    }

    func generateTodayArticles() async throws -> [Article] {
        let words = try await maiMemo.fetchTodayWords(limit: todayWordLimit)
        guard !words.isEmpty else { return [] }

        let batches = stride(from: 0, to: words.count, by: batchSize).map {
            Array(words[$0..<min($0 + batchSize, words.count)])
        }
        let scenes = ArticleScene.allCases

        return try await withThrowingTaskGroup(of: Article.self) { group in
            for (index, batch) in batches.enumerated() {
                let scene = scenes[index % scenes.count]
                group.addTask {
                    try await self.llm.generateArticle(words: batch, scene: scene)
                }
            }
            var articles: [Article] = []
            for try await article in group {
                articles.append(article)
            }
            return articles.sorted { a, b in
                guard let firstA = a.targetWords.first, let firstB = b.targetWords.first else { return false }
                return firstA.spelling < firstB.spelling
            }
        }
    }
}
