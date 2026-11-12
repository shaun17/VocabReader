import Foundation

protocol WordTranslatorServiceProtocol {
    func translate(word: String) async throws -> String
}

protocol ArticleParagraphTranslatorProtocol {
    func translate(paragraph: String) async throws -> String
    func analyze(paragraph: String) async throws -> String
}

final class WordTranslatorService {
    private static let textRequestMaxAttempts = 2
    private static let maximumRetryTokenLimit = 4_096

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

        return try await performLLMTextRequest(prompt: prompt, maxTokens: config.translationMaxTokens)
    }

    func translate(paragraph: String) async throws -> String {
        let prompt = """
        Translate the following English paragraph into accurate, natural Chinese.
        Preserve the paragraph structure and line breaks when possible.
        Return only the Chinese translation without explanation, numbering, or extra commentary.

        Paragraph:
        \(paragraph)
        """

        return try await performLLMTextRequest(prompt: prompt, maxTokens: config.paragraphTranslationMaxTokens)
    }

    func analyze(paragraph: String) async throws -> String {
        let prompt = """
        Analyze the following English paragraph for Chinese learners.
        Explain only practical language points that help the reader quickly understand and use the paragraph: grammar patterns, idioms, slang, implied tone, sentence logic, and natural expression habits.
        Do not translate the whole paragraph. Do not explain every word mechanically.
        Return valid JSON only. Do not use Markdown, numbering, or code fences.
        The JSON must match this schema exactly:
        {
          "points": [
            {
              "category": "语法结构|表达/俚语|语气逻辑",
              "quote": "an exact short phrase from the paragraph",
              "explanation": "why this wording matters in this paragraph, in concise Simplified Chinese",
              "usage": "one reusable usage tip for the learner, in concise Simplified Chinese"
            }
          ]
        }
        Include 2-4 points. Prefer the order: grammar patterns, idioms or natural expressions, then implied tone or sentence logic.
        Each point must be practical, reusable, and focused on understanding or using English naturally.

        Paragraph:
        \(paragraph)
        """

        let rawAnalysis = try await performLLMTextRequest(prompt: prompt, maxTokens: config.paragraphAnalysisMaxTokens)
        return Self.formattedParagraphAnalysis(from: rawAnalysis)
    }

    /// 发送通用 LLM 文本请求；截断、空正文和资源中断只允许受控重试一次。
    private func performLLMTextRequest(prompt: String, maxTokens: Int) async throws -> String {
        var currentMaxTokens = maxTokens
        var lastRetryableError = LLMError.noChoices

        for _ in 0..<Self.textRequestMaxAttempts {
            let choice = try await requestLLMTextCompletion(
                prompt: prompt,
                maxTokens: currentMaxTokens
            )

            switch choice.finishReason {
            case "length":
                lastRetryableError = .responseTruncated
                currentMaxTokens = min(currentMaxTokens * 2, Self.maximumRetryTokenLimit)
                continue
            case "insufficient_system_resource":
                lastRetryableError = .temporarilyUnavailable
                continue
            case "content_filter":
                throw LLMError.contentFiltered
            case "tool_calls":
                throw LLMError.invalidResponse
            default:
                let content = choice.message.content?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard content.isEmpty else { return content }
                lastRetryableError = .noChoices
            }
        }

        throw lastRetryableError
    }

    /// 执行单次兼容 OpenAI 协议的请求，并保留 finish_reason 供上层判断响应是否完整。
    private func requestLLMTextCompletion(
        prompt: String,
        maxTokens: Int
    ) async throws -> ChatCompletionResponse.Choice {
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
        if config.shouldDisableThinking {
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
        guard let choice = decoded.choices.first else {
            throw LLMError.noChoices
        }
        return choice
    }
}

extension WordTranslatorService: WordTranslatorServiceProtocol, ArticleParagraphTranslatorProtocol {}

private extension WordTranslatorService {
    /// 将模型返回的结构化解析统一渲染成固定栏目；模型偶尔未按 JSON 返回时也做稳定降级。
    static func formattedParagraphAnalysis(from rawAnalysis: String) -> String {
        if let payload = ParagraphAnalysisPayload.decode(from: rawAnalysis), !payload.points.isEmpty {
            return formattedStructuredAnalysis(payload.points)
        }

        return formattedFallbackAnalysis(rawAnalysis)
    }

    /// 按固定栏目顺序输出，保证不同模型返回的条目在界面上保持同一阅读节奏。
    static func formattedStructuredAnalysis(_ points: [ParagraphAnalysisPoint]) -> String {
        let groupedPoints = Dictionary(grouping: points, by: { normalizedCategory($0.category) })
        let orderedCategories = ParagraphAnalysisCategory.allCases.filter {
            groupedPoints[$0]?.isEmpty == false
        }

        return orderedCategories
            .map { category in
                let body = (groupedPoints[category] ?? [])
                    .map(formattedPoint)
                    .joined(separator: "\n")
                return "\(category.displayTitle)\n\(body)"
            }
            .joined(separator: "\n\n")
    }

    /// 将未结构化的编号、短横线或 Markdown 文本降级成统一的“语言观察”样式。
    static func formattedFallbackAnalysis(_ rawAnalysis: String) -> String {
        let lines = rawAnalysis
            .components(separatedBy: .newlines)
            .map(normalizedFallbackLine)
            .filter { !$0.isEmpty }

        let body = lines
            .map { "• \($0)" }
            .joined(separator: "\n")

        return body.isEmpty ? "语言观察\n• 暂无可展示的解析。" : "语言观察\n\(body)"
    }

    /// 输出单条解析时固定“原文、作用、记忆”三个字段，避免自由文本散乱。
    static func formattedPoint(_ point: ParagraphAnalysisPoint) -> String {
        let quote = sanitizedDisplayText(point.quote)
        let explanation = sanitizedDisplayText(point.explanation)
        let usage = sanitizedDisplayText(point.usage)

        var lines: [String] = []
        if !quote.isEmpty {
            lines.append("• 原文：\(quote)")
        }
        if !explanation.isEmpty {
            lines.append("  作用：\(explanation)")
        }
        if !usage.isEmpty {
            lines.append("  记忆：\(usage)")
        }

        return lines.isEmpty ? "• 暂无可展示的解析。" : lines.joined(separator: "\n")
    }

    /// 统一模型可能返回的近似分类，保持界面栏目稳定。
    static func normalizedCategory(_ category: String) -> ParagraphAnalysisCategory {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("语法") {
            return .grammar
        }
        if trimmed.contains("表达") || trimmed.contains("俚语") || trimmed.contains("习惯") {
            return .expression
        }
        if trimmed.contains("语气") || trimmed.contains("逻辑") || trimmed.contains("句子") {
            return .tone
        }
        return .observation
    }

    /// 清理模型降级文本里的编号、项目符号和 Markdown 标记。
    static func normalizedFallbackLine(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            #"^\d+[\.\)、\)]\s*"#,
            #"^[-*•]\s*"#,
            #"^#+\s*"#
        ]

        for pattern in prefixes {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return sanitizedDisplayText(result)
    }

    /// 去掉 Markdown 粗体等界面不直接渲染的标记，避免解析区出现技术符号。
    static func sanitizedDisplayText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}

private enum ParagraphAnalysisCategory: CaseIterable {
    case grammar
    case expression
    case tone
    case observation

    var displayTitle: String {
        switch self {
        case .grammar:
            return "语法结构"
        case .expression:
            return "表达与俚语"
        case .tone:
            return "语气与逻辑"
        case .observation:
            return "语言观察"
        }
    }
}

private struct ParagraphAnalysisPayload: Decodable {
    let points: [ParagraphAnalysisPoint]

    /// 兼容模型返回裸 JSON、代码块、前缀标题，以及外层 JSON 被截断但条目完整的常见形态。
    static func decode(from rawAnalysis: String) -> ParagraphAnalysisPayload? {
        let cleaned = rawAnalysis
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in strictPayloadCandidates(from: cleaned) {
            guard let data = candidate.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(ParagraphAnalysisPayload.self, from: data) else {
                continue
            }
            return payload
        }

        let points = loosePointCandidates(from: cleaned)
            .compactMap { candidate -> ParagraphAnalysisPoint? in
                guard let data = candidate.data(using: .utf8),
                      let point = try? JSONDecoder().decode(ParagraphAnalysisPoint.self, from: data),
                      point.hasDisplayableContent else {
                    return nil
                }
                return point
            }

        return points.isEmpty ? nil : ParagraphAnalysisPayload(points: points)
    }

    /// 提供完整 JSON 的候选范围；模型有时会在 JSON 前后额外写标题。
    private static func strictPayloadCandidates(from text: String) -> [String] {
        var candidates = [text]
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            candidates.append(String(text[firstBrace...lastBrace]))
        }
        return candidates
    }

    /// 从不完整 JSON 文本里提取已闭合的对象片段，尽量保住已经生成完整的解析条目。
    private static func loosePointCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        var objectStartStack: [String.Index] = []
        var index = text.startIndex
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                objectStartStack.append(index)
            } else if character == "}", let startIndex = objectStartStack.popLast() {
                candidates.append(String(text[startIndex...index]))
            }

            index = text.index(after: index)
        }

        return candidates
    }
}

private struct ParagraphAnalysisPoint: Decodable {
    let category: String
    let quote: String
    let explanation: String
    let usage: String

    private enum CodingKeys: String, CodingKey {
        case category
        case quote
        case explanation
        case usage
    }

    /// 允许模型漏掉非核心字段，避免结构化 JSON 因单个字段缺失而退回原文展示。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        quote = try container.decodeIfPresent(String.self, forKey: .quote) ?? ""
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        usage = try container.decodeIfPresent(String.self, forKey: .usage) ?? ""
    }

    /// 判断条目是否足够展示，避免把空对象或外层 payload 当成解析内容。
    var hasDisplayableContent: Bool {
        !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Word lookup

/// 阅读页查词面板的完整词条：文中释义、常见词义、原句译文与搭配，一次 LLM 请求拿全。
struct WordLookupResult: Equatable, Decodable {
    struct Sense: Equatable, Decodable {
        var partOfSpeech: String
        var meaning: String

        init(partOfSpeech: String, meaning: String) {
            self.partOfSpeech = partOfSpeech
            self.meaning = meaning
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            partOfSpeech = (try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "").trimmed
            meaning = (try container.decodeIfPresent(String.self, forKey: .meaning) ?? "").trimmed
        }

        private enum CodingKeys: String, CodingKey { case partOfSpeech, meaning }
    }

    struct Collocation: Equatable, Decodable {
        var phrase: String
        var meaning: String

        init(phrase: String, meaning: String) {
            self.phrase = phrase
            self.meaning = meaning
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phrase = (try container.decodeIfPresent(String.self, forKey: .phrase) ?? "").trimmed
            meaning = (try container.decodeIfPresent(String.self, forKey: .meaning) ?? "").trimmed
        }

        private enum CodingKeys: String, CodingKey { case phrase, meaning }
    }

    var phonetic: String
    var partOfSpeech: String
    var contextMeaning: String
    var contextNote: String
    var senses: [Sense]
    var sentenceTranslation: String
    var collocations: [Collocation]

    init(
        phonetic: String = "",
        partOfSpeech: String = "",
        contextMeaning: String,
        contextNote: String = "",
        senses: [Sense] = [],
        sentenceTranslation: String = "",
        collocations: [Collocation] = []
    ) {
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.contextMeaning = contextMeaning
        self.contextNote = contextNote
        self.senses = senses
        self.sentenceTranslation = sentenceTranslation
        self.collocations = collocations
    }

    /// 字段全部可缺省：模型漏写某一栏时只隐藏那一栏，不让整张词条失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phonetic = (try container.decodeIfPresent(String.self, forKey: .phonetic) ?? "").trimmed
        partOfSpeech = (try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "").trimmed
        contextMeaning = (try container.decodeIfPresent(String.self, forKey: .contextMeaning) ?? "").trimmed
        contextNote = (try container.decodeIfPresent(String.self, forKey: .contextNote) ?? "").trimmed
        senses = (try container.decodeIfPresent([Sense].self, forKey: .senses) ?? [])
            .filter { !$0.meaning.isEmpty }
        sentenceTranslation = (try container.decodeIfPresent(String.self, forKey: .sentenceTranslation) ?? "").trimmed
        collocations = (try container.decodeIfPresent([Collocation].self, forKey: .collocations) ?? [])
            .filter { !$0.phrase.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case phonetic, partOfSpeech, contextMeaning, contextNote, senses, sentenceTranslation, collocations
    }

    /// 兼容裸 JSON、代码块包裹和 JSON 前后夹带说明文字；至少要有一个释义才算有效。
    static func decode(from raw: String) -> WordLookupResult? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)

        var candidates = [cleaned]
        if let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}"), first < last {
            candidates.append(String(cleaned[first...last]))
        }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let result = try? JSONDecoder().decode(WordLookupResult.self, from: data),
                  !result.contextMeaning.isEmpty || !result.senses.isEmpty else {
                continue
            }
            return result
        }
        return nil
    }
}

enum WordLookupError: LocalizedError {
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .unreadableResponse: return "词条没有按格式返回，请重试"
        }
    }
}

protocol WordLookupServiceProtocol {
    func lookUp(word: String, sentence: String) async throws -> WordLookupResult
}

extension WordTranslatorService: WordLookupServiceProtocol {
    private static let lookupMaxTokens = 700

    func lookUp(word: String, sentence: String) async throws -> WordLookupResult {
        let prompt = """
        You are a concise English-Chinese learner's dictionary.
        Explain the English word or phrase "\(word)" as it is used in this sentence:
        \(sentence)

        Return valid JSON only, with no Markdown or code fences, matching this schema exactly:
        {
          "phonetic": "IPA in slashes, e.g. /ˈhɒrə/; empty string for multi-word phrases",
          "partOfSpeech": "part of speech in this sentence, abbreviated like n. / v. / adj. / adv. / phr.",
          "contextMeaning": "the Chinese meaning in this sentence, at most 12 characters",
          "contextNote": "one short Simplified Chinese sentence on nuance or tone here; empty string if nothing notable",
          "senses": [{"partOfSpeech": "n.", "meaning": "common Chinese meaning"}],
          "sentenceTranslation": "natural Simplified Chinese translation of the whole sentence",
          "collocations": [{"phrase": "common English collocation", "meaning": "Chinese meaning"}]
        }
        Give 2-3 senses ordered by frequency (the first may repeat the context meaning) and 2-3 everyday collocations.
        """

        let raw = try await performLLMTextRequest(prompt: prompt, maxTokens: Self.lookupMaxTokens)
        guard let result = WordLookupResult.decode(from: raw) else {
            throw WordLookupError.unreadableResponse
        }
        return result
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
