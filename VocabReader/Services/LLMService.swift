import Foundation

enum LLMError: Error, LocalizedError {
    case httpError(Int, String?)
    case noChoices
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            if let body { return "LLM HTTP \(code): \(body.prefix(200))" }
            return "LLM HTTP 错误 \(code)"
        case .noChoices: return "LLM 未返回任何内容"
        case .invalidResponse: return "LLM 请求地址无效，请检查 Base URL"
        }
    }
}

struct LLMConfig {
    var apiKey: String
    var baseURL: String
    var model: String
}

protocol LLMServiceProtocol {
    func generateArticle(words: [VocabWord], scene: ArticleScene) async throws -> Article
}

final class LLMService {
    private let config: LLMConfig
    private let session: URLSessionProtocol

    init(config: LLMConfig, session: URLSessionProtocol = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func generateArticle(words: [VocabWord], scene: ArticleScene) async throws -> Article {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw LLMError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let wordList = words.map { $0.spelling }.joined(separator: ", ")
        let prompt = """
        Write \(scene.promptDescription) of 4-6 paragraphs that naturally incorporates \
        ALL of these English vocabulary words: \(wordList). \
        Each word must appear in its original spelling. \
        The writing should flow naturally — do not bold or mark the words. \
        Output only the article text, no titles or extra commentary.
        """

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw LLMError.httpError(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMError.noChoices
        }

        return Article(id: UUID(), scene: scene, content: content, targetWords: words)
    }
}

extension LLMService: LLMServiceProtocol {}

// MARK: - Response types (private)

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }
}
