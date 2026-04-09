import Foundation
import os

enum LLMError: Error, LocalizedError {
    case httpError(Int, String?)
    case noChoices
    case invalidResponse
    case requestTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            if let body { return "LLM HTTP \(code): \(body.prefix(200))" }
            return "LLM HTTP 错误 \(code)"
        case .noChoices: return "LLM 未返回任何内容"
        case .invalidResponse: return "LLM 请求地址无效，请检查 Base URL"
        case .requestTimedOut(let timeout): return "LLM 请求超时，已等待 \(Int(timeout)) 秒"
        }
    }
}

struct LLMConfig {
    var apiKey: String
    var baseURL: String
    var model: String
    var requestTimeout: TimeInterval = 180
    var articleMaxTokens: Int = 900
    var translationMaxTokens: Int = 80
    var paragraphTranslationMaxTokens: Int = 240

    var usesKimiCompatibilityMode: Bool {
        let normalizedModel = model.lowercased()
        if normalizedModel.contains("kimi") {
            return true
        }

        guard let host = URL(string: baseURL)?.host?.lowercased() else {
            return false
        }
        return host.contains("moonshot.cn") || host.contains("kimi.com")
    }
}

protocol LLMServiceProtocol {
    func generateArticle(words: [VocabWord], scene: ArticleScene) async throws -> Article
}

protocol LLMConnectionTesting {
    func testConnection() async throws
}

final class LLMService {
    private static let logger = Logger(subsystem: "com.vocabreader.app", category: "LLMService")

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
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let wordList = words.map { $0.spelling }.joined(separator: ", ")
        let prompt = """
        Write \(scene.promptDescription) that naturally incorporates \
        ALL of these English vocabulary words: \(wordList). \
        Each word must appear in its original spelling. \
        The article as a whole must include ALL of the listed vocabulary words. \
        \(scene.formatInstructions) \
        Grammar, punctuation, and word usage must be accurate and natural. \
        The writing should flow naturally. Do not bold, mark, or explain the words separately. \
        Output only the article text, no titles or extra commentary.
        """

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.articleMaxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        if config.usesKimiCompatibilityMode {
            body["thinking"] = ["type": "disabled"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        Self.logger.info("Starting article generation for \(words.count) words with model \(self.config.model, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            let elapsed = Date().timeIntervalSince(startedAt)
            Self.logger.error("LLM request timed out after \(elapsed, privacy: .public)s")
            throw LLMError.requestTimedOut(config.requestTimeout)
        } catch {
            Self.logger.error("LLM request failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            Self.logger.error("LLM HTTP status \(http.statusCode, privacy: .public)")
            throw LLMError.httpError(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMError.noChoices
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        Self.logger.info("LLM article generation finished in \(elapsed, privacy: .public)s")

        return Article(id: UUID(), scene: scene, content: content, targetWords: words)
    }
}

extension LLMService: LLMServiceProtocol {}

extension LLMService: LLMConnectionTesting {
    func testConnection() async throws {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw LLMError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": 8,
            "messages": [
                ["role": "user", "content": "Reply with OK."]
            ]
        ]
        if config.usesKimiCompatibilityMode {
            body["thinking"] = ["type": "disabled"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw LLMError.httpError(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw LLMError.noChoices
        }
    }
}

// MARK: - Response types (private)

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let role: String
        let content: String?
    }
}
