import Foundation

protocol WordTranslatorServiceProtocol {
    func translate(word: String) async throws -> String
}

protocol ArticleParagraphTranslatorProtocol {
    func translate(paragraph: String) async throws -> String
}

final class WordTranslatorService {
    private let config: LLMConfig
    private let session: URLSessionProtocol

    init(config: LLMConfig, session: URLSessionProtocol = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func translate(word: String) async throws -> String {
        let prompt = """
        Translate the English word "\(word)" into concise natural Chinese.
        Return only the Chinese translation without explanation, examples, numbering, or extra punctuation.
        """

        return try await performTranslationRequest(prompt: prompt, maxTokens: config.translationMaxTokens)
    }

    func translate(paragraph: String) async throws -> String {
        let prompt = """
        Translate the following English paragraph into accurate, natural Chinese.
        Preserve the paragraph structure and line breaks when possible.
        Return only the Chinese translation without explanation, numbering, or extra commentary.

        Paragraph:
        \(paragraph)
        """

        return try await performTranslationRequest(prompt: prompt, maxTokens: config.paragraphTranslationMaxTokens)
    }

    private func performTranslationRequest(prompt: String, maxTokens: Int) async throws -> String {
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
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        if config.usesKimiCompatibilityMode {
            body["thinking"] = ["type": "disabled"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.requestTimedOut(config.requestTimeout)
        }
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

        return content
    }
}

extension WordTranslatorService: WordTranslatorServiceProtocol, ArticleParagraphTranslatorProtocol {}
