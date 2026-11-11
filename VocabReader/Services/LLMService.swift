import Foundation
import os

enum LLMError: Error, LocalizedError {
    case httpError(Int, String?)
    case noChoices
    case invalidResponse
    case requestTimedOut(TimeInterval)
    case responseTruncated
    case contentFiltered
    case temporarilyUnavailable
    case missingVocabularyWords([String])

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return Self.httpErrorDescription(code, serverMessage: Self.serverMessage(from: body))
        case .noChoices: return "LLM 未返回任何内容"
        case .invalidResponse: return "LLM 请求地址无效，请检查 Base URL"
        case .requestTimedOut(let timeout): return "LLM 请求超时，已等待 \(Int(timeout)) 秒"
        case .responseTruncated: return "LLM 输出长度不足，未能返回完整内容"
        case .contentFiltered: return "LLM 内容被安全策略拦截"
        case .temporarilyUnavailable: return "LLM 推理资源暂时不足，请稍后重试"
        case .missingVocabularyWords(let words): return "生成文章缺少目标词：\(words.joined(separator: ", "))"
        }
    }

    /// 状态码含义参照 DeepSeek 错误码文档，其他 OpenAI 兼容服务基本一致。
    private static func httpErrorDescription(_ code: Int, serverMessage: String?) -> String {
        let detail = serverMessage.map { "：\($0)" } ?? ""
        switch code {
        case 400:
            return "LLM 请求格式错误（HTTP 400）\(detail)"
        case 401:
            return "LLM API Key 无效（HTTP 401），请在设置中检查 API Key"
        case 402:
            return "LLM 账户余额不足（HTTP 402），请充值后重试"
        case 403:
            return "LLM 拒绝访问（HTTP 403），请确认 API Key 权限\(detail)"
        case 404:
            return "LLM 接口或模型不存在（HTTP 404），请检查 Base URL 和模型名称"
        case 422:
            return "LLM 请求参数错误（HTTP 422）\(detail)"
        case 429:
            return "LLM 请求速率达到上限（HTTP 429），请稍后重试"
        case 502, 503, 504:
            return "LLM 服务器繁忙（HTTP \(code)），请稍后重试"
        case 500..<600:
            return "LLM 服务器内部故障（HTTP \(code)），请稍后重试"
        default:
            return "LLM 请求失败（HTTP \(code)）\(detail)"
        }
    }

    /// 从 OpenAI 兼容错误体 `{"error":{"message":...}}` 中提取说明，非 JSON 时截取原文。
    private static func serverMessage(from body: String?) -> String? {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return String(message.prefix(200))
        }
        return String(body.prefix(200))
    }
}

struct LLMConfig {
    var apiKey: String
    var baseURL: String
    var model: String
    var requestTimeout: TimeInterval = 180
    var articleMaxTokens: Int = 1600
    var translationMaxTokens: Int = 80
    var paragraphTranslationMaxTokens: Int = 240
    var paragraphAnalysisMaxTokens: Int = 900

    /// DeepSeek 与 Kimi 都支持 thinking 开关；阅读类任务关闭思考，避免推理占用正文 token 预算。
    var shouldDisableThinking: Bool {
        let normalizedModel = model.lowercased()
        if normalizedModel.contains("kimi") || normalizedModel.contains("deepseek") {
            return true
        }

        guard let host = URL(string: baseURL)?.host?.lowercased() else {
            return false
        }
        return host.contains("moonshot.cn") ||
            host.contains("kimi.com") ||
            host.contains("deepseek.com")
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
    private static let articleGenerationRetryLimit = 3
    private static let sectionedArticleWordThreshold = 20
    private static let articleSectionWordLimit = 10
    private static let articleRequestTimeout: TimeInterval = 45
    private static let connectionTestMaxTokens = 64

    private let config: LLMConfig
    private let difficulty: ArticleDifficulty
    private let session: URLSessionProtocol

    init(
        config: LLMConfig,
        difficulty: ArticleDifficulty = .default,
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.config = config
        self.difficulty = difficulty
        self.session = session
    }

    /// 调用 LLM 生成文章，并同时注入体裁、主题和真实性约束。
    func generateArticle(words: [VocabWord], scene: ArticleScene, topic: ArticleTopic) async throws -> Article {
        if words.count > Self.sectionedArticleWordThreshold {
            return try await generateSectionedArticle(words: words, scene: scene, topic: topic)
        }

        return try await generateSinglePassArticle(words: words, scene: scene, topic: topic)
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
            "max_tokens": Self.connectionTestMaxTokens,
            "messages": [
                ["role": "user", "content": "Reply with OK."]
            ]
        ]
        if config.shouldDisableThinking {
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
    /// 小批次走单次完整生成；缺词时基于同一草稿修订，避免重新随机选题。
    func generateSinglePassArticle(words: [VocabWord], scene: ArticleScene, topic: ArticleTopic) async throws -> Article {
        var missingWords: [VocabWord] = []
        var bestDraft: ArticleDraftCandidate?
        let promptVocabulary = Self.promptVocabularyItems(for: words)
        let markerWordByID = Self.markerWordByID(from: promptVocabulary)
        let markerIDByWordID = Self.markerIDByWordID(from: promptVocabulary)
        let markupParser = ArticleVocabularyMarkupParser()

        for _ in 1...Self.articleGenerationMaxAttempts(for: words.count) {
            let prompt = buildArticlePrompt(
                promptVocabulary: promptVocabulary,
                wordCount: words.count,
                scene: scene,
                topic: topic,
                missingWords: missingWords,
                previousDraft: bestDraft
            )
            let content = try await requestArticleContent(prompt: prompt, wordCount: words.count)
            let parsed = Self.parseTitleAndBody(from: content, scene: scene)
            let cleanTitle = markupParser.parse(content: parsed.title, targetWords: []).content
            let markedBody = markupParser.parse(
                content: parsed.body,
                targetWords: words,
                markerWordByID: markerWordByID
            )
            let draft = ArticleDraftCandidate(
                title: cleanTitle,
                body: markedBody.content,
                occurrences: markedBody.occurrences,
                missingWords: markedBody.missingWords,
                markerIDByWordID: markerIDByWordID
            )

            guard !draft.missingWords.isEmpty else {
                return Article(
                    id: UUID(),
                    scene: scene,
                    topic: topic,
                    title: draft.title,
                    content: draft.body,
                    targetWords: words,
                    vocabularyOccurrences: draft.occurrences
                )
            }

            bestDraft = Self.betterDraft(current: bestDraft, candidate: draft)
            missingWords = draft.missingWords
            let missingWordList = draft.missingWords.map(\.spelling).joined(separator: ", ")
            Self.logger.warning("Generated article missed vocabulary words: \(missingWordList, privacy: .public)")
        }

        let bestMissingWords = bestDraft?.missingWords ?? missingWords
        throw LLMError.missingVocabularyWords(bestMissingWords.map(\.spelling))
    }

    /// 大批次按同一篇文章的连续段落生成，每段只负责一小组词，降低模型漏词概率。
    func generateSectionedArticle(words: [VocabWord], scene: ArticleScene, topic: ArticleTopic) async throws -> Article {
        let fullVocabulary = Self.promptVocabularyItems(for: words)
        let sections = Self.balancedChunks(fullVocabulary, maxSize: Self.articleSectionWordLimit)
        var title = ""
        var combinedBody = ""
        var combinedOccurrences: [ArticleVocabularyOccurrence] = []

        for (sectionOffset, sectionVocabulary) in sections.enumerated() {
            let section = try await generateArticleSection(
                sectionVocabulary: sectionVocabulary,
                fullVocabulary: fullVocabulary,
                totalWordCount: words.count,
                sectionIndex: sectionOffset + 1,
                sectionCount: sections.count,
                previousBody: combinedBody,
                scene: scene,
                topic: topic
            )
            if sectionOffset == 0 {
                title = section.title
            }
            if !combinedBody.isEmpty {
                combinedBody += "\n\n"
            }
            let sectionStart = (combinedBody as NSString).length
            combinedBody += section.body
            combinedOccurrences.append(
                contentsOf: Self.offsetOccurrences(section.occurrences, by: sectionStart)
            )
        }

        let combinedDraft = Self.draftByMergingSectionResults(
            title: title,
            body: combinedBody,
            words: words,
            sectionOccurrences: combinedOccurrences
        )

        guard !combinedDraft.missingWords.isEmpty else {
            return Article(
                id: UUID(),
                scene: scene,
                topic: topic,
                title: combinedDraft.title,
                content: combinedDraft.body,
                targetWords: words,
                vocabularyOccurrences: combinedDraft.occurrences
            )
        }

        throw LLMError.missingVocabularyWords(combinedDraft.missingWords.map(\.spelling))
    }

    /// 生成某一段并校验本段负责的目标词；失败时只修订这一段，避免整篇反复重写。
    func generateArticleSection(
        sectionVocabulary: [PromptVocabularyItem],
        fullVocabulary: [PromptVocabularyItem],
        totalWordCount: Int,
        sectionIndex: Int,
        sectionCount: Int,
        previousBody: String,
        scene: ArticleScene,
        topic: ArticleTopic
    ) async throws -> ArticleDraftCandidate {
        var missingWords: [VocabWord] = []
        var bestDraft: ArticleDraftCandidate?
        let sectionWords = sectionVocabulary.map(\.word)
        let markerWordByID = Self.markerWordByID(from: sectionVocabulary)
        let markerIDByWordID = Self.markerIDByWordID(from: sectionVocabulary)
        let markupParser = ArticleVocabularyMarkupParser()

        for _ in 1...Self.articleGenerationMaxAttempts(for: sectionWords.count) {
            let prompt = buildArticleSectionPrompt(
                sectionVocabulary: sectionVocabulary,
                fullVocabulary: fullVocabulary,
                totalWordCount: totalWordCount,
                sectionIndex: sectionIndex,
                sectionCount: sectionCount,
                previousBody: previousBody,
                scene: scene,
                topic: topic,
                missingWords: missingWords,
                previousDraft: bestDraft
            )
            let content = try await requestArticleContent(prompt: prompt, wordCount: totalWordCount)
            let parsed = Self.parseSectionTitleAndBody(from: content, sectionIndex: sectionIndex, scene: scene)
            let cleanTitle = Self.cleanedSectionTitle(
                markupParser.parse(content: parsed.title, targetWords: []).content
            )
            let markedBody = markupParser.parse(
                content: parsed.body,
                targetWords: sectionWords,
                markerWordByID: markerWordByID
            )
            let draft = ArticleDraftCandidate(
                title: cleanTitle,
                body: markedBody.content,
                occurrences: markedBody.occurrences,
                missingWords: markedBody.missingWords,
                markerIDByWordID: markerIDByWordID
            )

            guard !draft.missingWords.isEmpty else { return draft }

            bestDraft = Self.betterDraft(current: bestDraft, candidate: draft)
            missingWords = draft.missingWords
            let missingWordList = draft.missingWords.map(\.spelling).joined(separator: ", ")
            Self.logger.warning("Generated article section missed vocabulary words: \(missingWordList, privacy: .public)")
        }

        let bestMissingWords = bestDraft?.missingWords ?? missingWords
        throw LLMError.missingVocabularyWords(bestMissingWords.map(\.spelling))
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
        request.timeoutInterval = min(config.requestTimeout, Self.articleRequestTimeout)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.articleMaxTokens,
            "messages": [
                ["role": "system", "content": articleSystemPrompt()],
                ["role": "user", "content": prompt]
            ]
        ]
        if config.shouldDisableThinking {
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
            throw LLMError.requestTimedOut(request.timeoutInterval)
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

    /// 每次请求都不变的写作规则放进 system 消息，词表和本次任务放在 user 消息，便于服务端复用前缀缓存。
    func articleSystemPrompt() -> String {
        """
        You write short English reading passages that help Chinese learners review vocabulary in context.

        \(articleCoherenceInstruction())

        \(naturalEnglishInstruction())

        Target vocabulary rules:
        - Use each target item in its most common core meaning that fits the topic, which is the meaning a learner is most likely studying. Avoid rare, archaic, slang, or highly technical senses, and do not use target items in puns.
        - Each target item must appear as its original spelling or a natural inflected form, such as a plural, a verb tense, or a comparative. Do not replace it with a derived word of a different part of speech, for example "decision" for "decide".
        - Spread the target items across the whole text. Do not turn the text into a vocabulary checklist or a word dump, and do not write a sentence that only exists to mention a word. Give each target item enough sentence context for a learner to understand how it is used in real communication.
        - In the body, wrap the exact visible words that cover each target item with <vocab id="TARGET_ID">actual words in the text</vocab>. Use each TARGET_ID exactly as listed and mark every required item at least once. Never put <vocab> tags in the title.

        Formatting rules:
        - Do not use Markdown emphasis such as **bold** or __bold__, headings, bullet markers, or code formatting. The <vocab> tag is the only allowed inline markup.
        - Do not define or explain the target words, and add no commentary outside the requested output tags.

        Before answering, check that every sentence is grammatical, every required target item is present and tagged, and the text reads as one connected piece.
        """
    }

    /// 拼装分段生成 Prompt，保证每次只覆盖当前段词汇，同时延续前文主线。
    func buildArticleSectionPrompt(
        sectionVocabulary: [PromptVocabularyItem],
        fullVocabulary: [PromptVocabularyItem],
        totalWordCount: Int,
        sectionIndex: Int,
        sectionCount: Int,
        previousBody: String,
        scene: ArticleScene,
        topic: ArticleTopic,
        missingWords: [VocabWord] = [],
        previousDraft: ArticleDraftCandidate? = nil
    ) -> String {
        let sectionRole = sectionIndex == 1
            ? "Start Section \(sectionIndex) of \(sectionCount)"
            : "Continue the same article with Section \(sectionIndex) of \(sectionCount)"
        let sectionName: String
        switch sectionIndex {
        case 1: sectionName = "opening"
        case sectionCount: sectionName = "closing"
        default: sectionName = "continuation"
        }
        let outputInstruction = sectionIndex == 1
            ? "Output the title as <title>a short title of 3-8 words</title>, then this tagged opening section as <body>...</body>."
            : "Output only this tagged \(sectionName) section as <body>...</body>. Do not add a new title."
        let planningInstruction = sectionIndex == 1
            ? "Before writing, silently choose one plausible central premise that gives every item in this full map a meaningful role."
            : "Use this full map to preserve the central premise and causal progression established by the opening section."
        let plan = ArticleLengthPlan(targetWordCount: sectionVocabulary.count)
        let isClosingSection = sectionIndex == sectionCount
        var positionInstructions: [String] = []
        if sectionIndex > 1 {
            positionInstructions.append("Pick up exactly where the previous content stops; do not re-introduce the setting, speakers, or topic.")
        }
        positionInstructions.append(isClosingSection
            ? "This is the closing section: bring the same situation to a clear resolution or conclusion."
            : "This is not the last section: keep the situation open and do not conclude or resolve the article yet.")

        return """
        \(sectionRole) for one \(scene.promptDescription) about \(topic.promptDescription). \
        This is one article split into \(sectionCount) connected generation steps, not \(sectionCount) separate articles. \
        Full-article vocabulary map: \(targetVocabularyInstruction(for: fullVocabulary)). \
        Only the CURRENT SECTION items are coverage requirements for this response; the full map is planning context only. \
        \(planningInstruction) \
        The full article will cover \(totalWordCount) target vocabulary items; this section must cover ALL of these current-section items: \(targetVocabularyInstruction(for: sectionVocabulary)). \
        \(difficulty.promptInstructions) \
        Write around \(plan.wordRange.lowerBound)-\(plan.wordRange.upperBound) English words for this \(sectionName) section. \
        \(scene.formatInstructions(for: plan, includesEnding: isClosingSection)) \
        Continue the same situation, question, explanation, or conflict. Do not restart, summarize, or switch topics between sections. \
        \(positionInstructions.joined(separator: " ")) \
        \(topic.topicInstructions) \
        \(topic.factConstraintInstructions)
        \(previousBodyInstruction(previousBody))
        \(missingSectionVocabularyInstruction(for: missingWords, previousDraft: previousDraft))
        \(outputInstruction)
        """
    }

    /// 拼装文章生成 Prompt，统一管理体裁、主题、难度、篇幅和真实性约束。
    func buildArticlePrompt(
        promptVocabulary: [PromptVocabularyItem],
        wordCount: Int,
        scene: ArticleScene,
        topic: ArticleTopic,
        missingWords: [VocabWord] = [],
        previousDraft: ArticleDraftCandidate? = nil
    ) -> String {
        let plan = ArticleLengthPlan(targetWordCount: wordCount)
        return """
        Write \(scene.promptDescription) about \(topic.promptDescription). \
        Target vocabulary items: \(targetVocabularyInstruction(for: promptVocabulary)). \
        The article as a whole must include ALL of the listed vocabulary words. \
        \(difficulty.promptInstructions) \
        Write around \(plan.wordRange.lowerBound)-\(plan.wordRange.upperBound) English words. \
        \(scene.formatInstructions(for: plan)) \
        \(articlePlanningInstruction()) \
        \(topic.topicInstructions) \
        \(topic.factConstraintInstructions)
        \(missingVocabularyInstruction(for: missingWords, previousDraft: previousDraft))
        Output the title as <title>a short title of 3-8 words</title>, then the tagged article body as <body>...</body>.
        """
    }

    /// 所有批次都整体重试，避免分页层把独立片段拼成上下文断裂的文章。
    static func articleGenerationMaxAttempts(for _: Int) -> Int {
        articleGenerationRetryLimit
    }

    /// 约束整篇文章必须围绕同一条主线展开，防止模型把目标词写成松散例句。
    func articleCoherenceInstruction() -> String {
        """
        Use one central through-line from beginning to end: one situation, question, explanation, or conflict. \
        Every sentence, paragraph, or dialogue turn must follow from the previous one through cause, contrast, reaction, clarification, or consequence. \
        Do not write isolated example sentences, disconnected facts, abrupt topic changes, or a list of separate mini-scenes.
        """
    }

    /// 先把随机词汇组织成一个可推进的情境，避免按词表顺序逐句造例句。
    func articlePlanningInstruction() -> String {
        """
        Before writing, silently choose one plausible central premise that gives every target vocabulary item a meaningful role. \
        Organize the article as a clear progression with an opening, development, and resolution or conclusion. \
        Treat the vocabulary list as material for that one premise, never as the order of sentences.
        """
    }

    /// 要求语法准确、搭配地道；具体句式难度由阅读难度设置决定。
    func naturalEnglishInstruction() -> String {
        """
        Grammar, punctuation, and word usage must be accurate and natural. \
        Prefer vocabulary, grammar, and phrasing that are common in contemporary everyday English. \
        Use natural collocations and sentence patterns that fluent speakers would normally choose. \
        Avoid literary, archaic, or needlessly convoluted constructions. \
        Never distort the meaning or grammar just to include a target word; choose a different sentence that uses it idiomatically.
        """
    }

    /// 给模型短标记 ID 和词面，避免真实词条 ID 太长导致标签截断。
    func targetVocabularyInstruction(for items: [PromptVocabularyItem]) -> String {
        items
            .map { "id=\($0.markerID), word=\($0.word.spelling)" }
            .joined(separator: "; ")
    }

    /// 把前文放进续写 Prompt，分隔清楚，避免模型把前文当成要重复输出的内容。
    func previousBodyInstruction(_ previousBody: String) -> String {
        let trimmedBody = previousBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return "" }

        return """
        Previous article content:
        \"\"\"
        \(trimmedBody)
        \"\"\"
        """
    }

    /// 生成重试提示，把上一版缺失的目标词明确反馈给模型。
    func missingVocabularyInstruction(for missingWords: [VocabWord], previousDraft: ArticleDraftCandidate?) -> String {
        guard !missingWords.isEmpty else { return "" }

        let missingWordList = missingWords.map(\.spelling).joined(separator: ", ")
        if let previousDraft, !previousDraft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return """
            Missing vocabulary words from the previous draft: \(missingWordList). \
            Revise this previous draft instead of starting over: keep the same through-line, keep every existing <vocab> tag, and insert the missing words naturally into the same article. Return the full corrected article in the same tagged format.
            Previous draft:
            \"\"\"
            \(previousDraft.formattedText)
            \"\"\"
            """
        }

        return """
        Missing vocabulary words from the previous draft: \(missingWordList). \
        Rewrite the whole article and include every missing vocabulary word naturally, using its original spelling or a natural inflected form, while keeping every other required vocabulary word covered.
        """
    }

    /// 分段重试只允许修订当前段，避免模型返回整篇正文后与既有前文重复拼接。
    func missingSectionVocabularyInstruction(
        for missingWords: [VocabWord],
        previousDraft: ArticleDraftCandidate?
    ) -> String {
        guard !missingWords.isEmpty else { return "" }

        let missingWordList = missingWords.map(\.spelling).joined(separator: ", ")
        if let previousDraft, !previousDraft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return """
            Missing vocabulary words from the previous section draft: \(missingWordList). \
            Revise only this section draft, preserve its connection to the established through-line, keep every existing <vocab> tag, and insert the missing words naturally. \
            Return the full corrected section. Do not repeat previous article content or add a title.
            Previous section draft:
            \"\"\"
            \(previousDraft.taggedBody)
            \"\"\"
            """
        }

        return """
        Missing vocabulary words from the previous section draft: \(missingWordList). \
        Rewrite only the current section so it includes every missing word naturally. Do not repeat previous article content or add a title.
        """
    }
}

// MARK: - Generation support

private struct PromptVocabularyItem {
    let markerID: String
    let word: VocabWord
}

private struct ArticleDraftCandidate {
    let title: String
    let body: String
    let occurrences: [ArticleVocabularyOccurrence]
    let missingWords: [VocabWord]
    var markerIDByWordID: [String: String] = [:]

    /// 把已覆盖的目标词重新套上 <vocab> 标签，重试时模型只需补缺词，不必重新标注已有的词。
    var taggedBody: String {
        let nsBody = body as NSString
        var result = ""
        var location = 0
        for occurrence in occurrences.sorted(by: { $0.range.location < $1.range.location }) {
            guard
                let markerID = markerIDByWordID[occurrence.word.id],
                occurrence.range.location >= location,
                NSMaxRange(occurrence.range) <= nsBody.length
            else { continue }
            result += nsBody.substring(with: NSRange(location: location, length: occurrence.range.location - location))
            result += "<vocab id=\"\(markerID)\">\(nsBody.substring(with: occurrence.range))</vocab>"
            location = NSMaxRange(occurrence.range)
        }
        result += nsBody.substring(from: location)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 给重试 Prompt 提供与要求输出一致的带标签草稿，让模型在同一篇文章内修订，而不是重新随机生成。
    var formattedText: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "<title>\(trimmedTitle)</title>\n<body>\(taggedBody)</body>"
    }
}

private extension LLMService {
    /// 为单次请求生成短标记 ID；真实词条 ID 只留在本地映射里，不交给模型复写。
    static func promptVocabularyItems(for words: [VocabWord]) -> [PromptVocabularyItem] {
        words.enumerated().map { index, word in
            PromptVocabularyItem(markerID: "w\(index + 1)", word: word)
        }
    }

    /// 建立真实词条到短标记 ID 的映射，用于把重试草稿还原成带标签的文本。
    static func markerIDByWordID(from items: [PromptVocabularyItem]) -> [String: String] {
        items.reduce(into: [String: String]()) { result, item in
            if result[item.word.id] == nil {
                result[item.word.id] = item.markerID
            }
        }
    }

    /// 建立短标记 ID 到真实词条的映射，用于解析模型返回的内联标记。
    static func markerWordByID(from items: [PromptVocabularyItem]) -> [String: VocabWord] {
        items.reduce(into: [String: VocabWord]()) { result, item in
            result[item.markerID] = item.word
        }
    }

    /// 合并分段结果时保留每段已确认的标记命中，再只对未覆盖词做本地扫词。
    static func draftByMergingSectionResults(
        title: String,
        body: String,
        words: [VocabWord],
        sectionOccurrences: [ArticleVocabularyOccurrence]
    ) -> ArticleDraftCandidate {
        let markedWordIDs = Set(sectionOccurrences.map(\.word.id))
        let unmarkedWords = words.filter { !markedWordIDs.contains($0.id) }
        let fallbackOccurrences = TargetWordMatcher(targetWords: unmarkedWords).occurrences(
            in: body,
            excluding: sectionOccurrences.map(\.range)
        )
        let allOccurrences = (sectionOccurrences + fallbackOccurrences).sorted {
            $0.range.location < $1.range.location
        }
        let coveredWordIDs = Set(allOccurrences.map(\.word.id))
        let missingWords = TargetWordMatcher.missingWords(
            in: body,
            targetWords: words.filter { !coveredWordIDs.contains($0.id) }
        )

        return ArticleDraftCandidate(
            title: title,
            body: body,
            occurrences: allOccurrences,
            missingWords: missingWords
        )
    }

    /// 分段正文合并时把段内命中位置平移到整篇正文的位置。
    static func offsetOccurrences(_ occurrences: [ArticleVocabularyOccurrence], by offset: Int) -> [ArticleVocabularyOccurrence] {
        occurrences.map { occurrence in
            ArticleVocabularyOccurrence(
                word: occurrence.word,
                surfaceText: occurrence.surfaceText,
                range: NSRange(
                    location: occurrence.range.location + offset,
                    length: occurrence.range.length
                )
            )
        }
    }

    /// 保留缺词最少的草稿；缺词数量相同时，保留正文更完整的一版。
    static func betterDraft(current: ArticleDraftCandidate?, candidate: ArticleDraftCandidate) -> ArticleDraftCandidate {
        guard let current else { return candidate }
        if candidate.missingWords.count < current.missingWords.count {
            return candidate
        }
        if candidate.missingWords.count == current.missingWords.count && candidate.body.count > current.body.count {
            return candidate
        }
        return current
    }

    /// 把大批次词汇均分成不超过 maxSize 的小段，避免最后一段只剩一两个词却要写一整段。
    static func balancedChunks<Element>(_ items: [Element], maxSize: Int) -> [[Element]] {
        guard maxSize > 0, !items.isEmpty else { return [items] }

        let chunkCount = (items.count + maxSize - 1) / maxSize
        let baseSize = items.count / chunkCount
        let largerChunkCount = items.count % chunkCount
        var chunks: [[Element]] = []
        var startIndex = 0
        for index in 0..<chunkCount {
            let size = baseSize + (index < largerChunkCount ? 1 : 0)
            chunks.append(Array(items[startIndex..<(startIndex + size)]))
            startIndex += size
        }
        return chunks
    }
}

// MARK: - Parsing

private extension LLMService {
    /// 优先读取 <title>/<body> 标签；模型没按标签输出时退回“第一行标题、其余正文”的旧格式。
    static func parseTitleAndBody(from raw: String, scene: ArticleScene) -> (title: String, body: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body = taggedContent("body", in: trimmed) {
            return (normalizedTitle(taggedContent("title", in: trimmed) ?? ""), body)
        }
        guard let firstNewline = trimmed.firstIndex(of: "\n") else {
            return ("", trimmed)
        }
        let titleCandidate = String(trimmed[..<firstNewline]).trimmingCharacters(in: .whitespacesAndNewlines)
        if treatsOpeningLineAsBody(titleCandidate, scene: scene) {
            return ("", trimmed)
        }

        let title = normalizedTitle(titleCandidate)
        let body = String(trimmed[firstNewline...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
    }

    /// 分段生成只有第一段允许带标题，后续段落全部按正文续写处理。
    static func parseSectionTitleAndBody(from raw: String, sectionIndex: Int, scene: ArticleScene) -> (title: String, body: String) {
        guard sectionIndex == 1 else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return ("", taggedContent("body", in: trimmed) ?? trimmed)
        }
        return parseTitleAndBody(from: raw, scene: scene)
    }

    /// 取出 <tag>...</tag> 之间的内容；输出被截断缺少闭合标签时取到文本末尾。
    static func taggedContent(_ tag: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(tag)>", options: .caseInsensitive) else { return nil }
        let rest = text[open.upperBound...]
        let close = rest.range(of: "</\(tag)>", options: .caseInsensitive)
        return String(rest[..<(close?.lowerBound ?? rest.endIndex)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 清掉模型偶尔写进标题的内部段落标记，避免用户看到生成步骤。
    static func cleanedSectionTitle(_ title: String) -> String {
        title
            .replacingOccurrences(
                of: #"(?i)\s*[-–—:]\s*section\s+\d+\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)^\s*section\s+\d+\s*[-–—:]\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DeepSeek 偶尔不返回标题，直接从对话正文开头；这时不能把首句当标题丢出正文校验。
    static func treatsOpeningLineAsBody(_ line: String, scene: ArticleScene) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scene == .dialogue else { return false }
        return trimmed.range(of: #"^[A-Z]\s*[:：]"#, options: .regularExpression) != nil
    }

    /// 兼容模型返回 "Title: ..." 这类标题前缀，避免 UI 上直接显示协议字段名。
    static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^title\s*[:：]\s*"#,
            #"^标题\s*[:：]\s*"#
        ]

        return patterns.reduce(trimmed) { current, pattern in
            current.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Response types (private)

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let role: String
        let content: String?
    }
}
