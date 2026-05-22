import Foundation

protocol WordTranslatorServiceProtocol {
    func translate(word: String) async throws -> String
}

protocol ArticleParagraphTranslatorProtocol {
    func translate(paragraph: String) async throws -> String
    func analyze(paragraph: String) async throws -> String
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

    /// 发送通用 LLM 文本请求，供查词、段落翻译和段落解析复用。
    private func performLLMTextRequest(prompt: String, maxTokens: Int) async throws -> String {
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

    /// 输出单条解析时固定“原文、作用、用法”三个字段，避免自由文本散乱。
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
            lines.append("  用法：\(usage)")
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

    /// 兼容模型返回裸 JSON 或 ```json 代码块两种常见形态。
    static func decode(from rawAnalysis: String) -> ParagraphAnalysisPayload? {
        let cleaned = rawAnalysis
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ParagraphAnalysisPayload.self, from: data)
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
}
