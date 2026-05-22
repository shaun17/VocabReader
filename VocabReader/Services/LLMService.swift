import Foundation
import os

enum LLMError: Error, LocalizedError {
    case httpError(Int, String?)
    case noChoices
    case invalidResponse
    case requestTimedOut(TimeInterval)
    case missingVocabularyWords([String])

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            if let body { return "LLM HTTP \(code): \(body.prefix(200))" }
            return "LLM HTTP 错误 \(code)"
        case .noChoices: return "LLM 未返回任何内容"
        case .invalidResponse: return "LLM 请求地址无效，请检查 Base URL"
        case .requestTimedOut(let timeout): return "LLM 请求超时，已等待 \(Int(timeout)) 秒"
        case .missingVocabularyWords(let words): return "生成文章缺少目标词：\(words.joined(separator: ", "))"
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
    var paragraphAnalysisMaxTokens: Int = 520

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
    func generateArticle(words: [VocabWord], scene: ArticleScene, topic: ArticleTopic) async throws -> Article
}

protocol LLMConnectionTesting {
    func testConnection() async throws
}

final class LLMService {
    private static let logger = Logger(subsystem: "com.vocabreader.app", category: "LLMService")
    private static let articleGenerationMaxAttempts = 3

    private let config: LLMConfig
    private let session: URLSessionProtocol

    init(config: LLMConfig, session: URLSessionProtocol = URLSession.shared) {
        self.config = config
        self.session = session
    }

    /// 调用 LLM 生成文章，并同时注入体裁、主题和真实性约束。
    func generateArticle(words: [VocabWord], scene: ArticleScene, topic: ArticleTopic) async throws -> Article {
        let wordList = words.map { $0.spelling }.joined(separator: ", ")
        var missingWords: [VocabWord] = []

        for _ in 1...Self.articleGenerationMaxAttempts {
            let prompt = buildArticlePrompt(
                words: wordList,
                wordCount: words.count,
                scene: scene,
                topic: topic,
                missingWords: missingWords
            )
            let content = try await requestArticleContent(prompt: prompt, wordCount: words.count)
            let parsed = Self.parseTitleAndBody(from: content)
            let currentMissingWords = TargetWordMatcher.missingWords(in: parsed.body, targetWords: words)

            guard !currentMissingWords.isEmpty else {
                return Article(id: UUID(), scene: scene, topic: topic, title: parsed.title, content: parsed.body, targetWords: words)
            }

            missingWords = currentMissingWords
            let missingWordList = currentMissingWords.map(\.spelling).joined(separator: ", ")
            Self.logger.warning("Generated article missed vocabulary words: \(missingWordList, privacy: .public)")
        }

        throw LLMError.missingVocabularyWords(missingWords.map(\.spelling))
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

private extension LLMService {
    /// 发送单次文章生成请求；是否重试由外层根据缺词校验决定。
    func requestArticleContent(prompt: String, wordCount: Int) async throws -> String {
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
        Self.logger.info("Starting article generation for \(wordCount, privacy: .public) words with model \(self.config.model, privacy: .public)")

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
        return content
    }

    /// 拼装文章生成 Prompt，统一管理体裁、主题和真实性约束。
    func buildArticlePrompt(
        words wordList: String,
        wordCount: Int,
        scene: ArticleScene,
        topic: ArticleTopic,
        missingWords: [VocabWord] = []
    ) -> String {
        """
        Write \(scene.promptDescription) about \(topic.promptDescription) that naturally incorporates \
        ALL of these English vocabulary words: \(wordList). \
        Each target vocabulary item must appear in the article as its original spelling or a natural inflected form in the same word family. \
        The article as a whole must include ALL of the listed vocabulary words. \
        \(articleLengthInstruction(for: wordCount)) \
        Spread the vocabulary across the whole article. Do not turn the article into a vocabulary checklist, a word dump, or one sentence that only exists to mention words. \
        Give each target word enough sentence context for a learner to understand how it is used in real communication. \
        \(scene.formatInstructions) \
        \(topic.topicInstructions) \
        \(topic.factConstraintInstructions) \
        Grammar, punctuation, and word usage must be accurate and natural. \
        The writing should flow naturally. Do not bold, mark, or explain the words separately. \
        \(missingVocabularyInstruction(for: missingWords)) \
        Output the title on the first line, then a blank line, then the article text. No extra commentary.
        """
    }

    /// 按目标词数量给模型明确篇幅，避免词多时生成一两句硬塞词的短文。
    func articleLengthInstruction(for wordCount: Int) -> String {
        switch wordCount {
        case ...10:
            return "Write around 90-140 English words."
        case 11...20:
            return "Write around 150-220 English words."
        case 21...30:
            return "Write around 220-320 English words."
        default:
            return "Write around 300-430 English words."
        }
    }

    /// 生成重试提示，把上一版缺失的目标词明确反馈给模型。
    func missingVocabularyInstruction(for missingWords: [VocabWord]) -> String {
        guard !missingWords.isEmpty else { return "" }

        let missingWordList = missingWords.map(\.spelling).joined(separator: ", ")
        return """
        Missing vocabulary words from the previous draft: \(missingWordList). \
        Rewrite the whole article and include every missing vocabulary word naturally, using its original spelling or a natural inflected form, while keeping every other required vocabulary word covered.
        """
    }
}

// MARK: - Parsing

private extension LLMService {
    /// 将 LLM 返回文本拆分为标题（第一行）和正文（剩余部分）。
    static func parseTitleAndBody(from raw: String) -> (title: String, body: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstNewline = trimmed.firstIndex(of: "\n") else {
            return ("", trimmed)
        }
        let title = String(trimmed[..<firstNewline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(trimmed[firstNewline...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
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
