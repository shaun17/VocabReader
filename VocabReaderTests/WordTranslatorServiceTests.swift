import XCTest
@testable import VocabReader

final class WordTranslatorServiceTests: XCTestCase {
    func testTranslateWordReturnsTranslatedContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "苹果"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let translation = try await service.translate(word: "apple")

        XCTAssertEqual(translation, "苹果")
    }

    func testTranslateWordBuildsPromptWithWord() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "苹果"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        _ = try await service.translate(word: "apple")

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("apple"))
    }

    func testTranslateParagraphReturnsTranslatedContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "A：你好，苹果。\\nB：你好，香蕉。"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let translation = try await service.translate(paragraph: "A: Hello, apple.\nB: Hi, banana.")

        XCTAssertEqual(translation, "A：你好，苹果。\nB：你好，香蕉。")
    }

    func testTranslateParagraphBuildsPromptWithParagraphAndKeepsStructure() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "译文"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        _ = try await service.translate(paragraph: "A: Hello, apple.\nB: Hi, banana.")

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let prompt = try XCTUnwrap(messages.first?["content"] as? String)

        XCTAssertTrue(prompt.contains("A: Hello, apple.\nB: Hi, banana."))
        XCTAssertTrue(prompt.contains("Preserve the paragraph structure and line breaks"))
        XCTAssertEqual(object["max_tokens"] as? Int, 240)
    }

    /// DeepSeek 默认开启思考模式；翻译任务必须显式关闭，确保 token 预算用于最终译文。
    func testTranslateParagraphDisablesThinkingForDeepSeek() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": "完整译文。"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash"
        )
        let service = WordTranslatorService(config: config, session: session)

        _ = try await service.translate(paragraph: "A: We should start again.\nB: The deadline is tomorrow.")

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
    }

    /// finish_reason=length 代表译文已截断，必须扩大输出预算重试，不能缓存半截内容。
    func testTranslateParagraphRetriesTruncatedCompletionAndReturnsCompleteTranslation() async throws {
        let truncatedJSON = """
        {
          "choices": [{"finish_reason": "length", "message": {"role": "assistant", "content": "A：我们可以放弃整个计划。这是个双"}}]
        }
        """
        let completeJSON = """
        {
          "choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": "A：我们可以放弃整个计划，从头再来。这是一个双赢局面。\\nB：但截止日期是明天。"}}]
        }
        """
        let session = QueueingMockSession(responses: [
            (Data(truncatedJSON.utf8), 200),
            (Data(completeJSON.utf8), 200)
        ])
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash"
        )
        let service = WordTranslatorService(config: config, session: session)

        let translation = try await service.translate(
            paragraph: "A: We could toss the whole plan and start fresh.\nB: But the deadline is tomorrow."
        )

        XCTAssertEqual(translation, "A：我们可以放弃整个计划，从头再来。这是一个双赢局面。\nB：但截止日期是明天。")
        XCTAssertEqual(session.requests.count, 2)
        let firstBody = try XCTUnwrap(session.requests.first?.httpBody)
        let secondBody = try XCTUnwrap(session.requests.last?.httpBody)
        let firstObject = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        XCTAssertEqual(firstObject["max_tokens"] as? Int, 240)
        XCTAssertEqual(secondObject["max_tokens"] as? Int, 480)
    }

    /// 兼容服务偶发返回 200 但正文为空的情况；一次重试成功后应恢复后续翻译和解析能力。
    func testTranslateParagraphRetriesEmptyCompletion() async throws {
        let emptyJSON = """
        {
          "choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": ""}}]
        }
        """
        let completeJSON = """
        {
          "choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": "这是完整译文。"}}]
        }
        """
        let session = QueueingMockSession(responses: [
            (Data(emptyJSON.utf8), 200),
            (Data(completeJSON.utf8), 200)
        ])
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash"
        )
        let service = WordTranslatorService(config: config, session: session)

        let translation = try await service.translate(paragraph: "This is a complete paragraph.")

        XCTAssertEqual(translation, "这是完整译文。")
        XCTAssertEqual(session.requests.count, 2)
    }

    func testAnalyzeParagraphReturnsStructuredAnalysisContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "{\\"points\\":[{\\"category\\":\\"语法结构\\",\\"quote\\":\\"Would you mind\\",\\"explanation\\":\\"用疑问句包装请求，语气更委婉。\\",\\"usage\\":\\"向别人提要求时，可用 Would you mind + doing。\\"},{\\"category\\":\\"表达/俚语\\",\\"quote\\":\\"opening the window\\",\\"explanation\\":\\"动名词跟在 mind 后，动作表达自然。\\",\\"usage\\":\\"mind 后接动名词，不接 to do。\\"}]}"} }]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let analysis = try await service.analyze(paragraph: "Would you mind opening the window?")

        XCTAssertEqual(
            analysis,
            """
            语法结构
            • 原文：Would you mind
              作用：用疑问句包装请求，语气更委婉。
              记忆：向别人提要求时，可用 Would you mind + doing。

            表达与俚语
            • 原文：opening the window
              作用：动名词跟在 mind 后，动作表达自然。
              记忆：mind 后接动名词，不接 to do。
            """
        )
    }

    func testAnalyzeParagraphNormalizesUnstructuredFallbackContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "1. 这里的 would 用来让请求更委婉。\\n2) mind 后面接动名词 opening。"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let analysis = try await service.analyze(paragraph: "Would you mind opening the window?")

        XCTAssertEqual(
            analysis,
            """
            语言观察
            • 这里的 would 用来让请求更委婉。
            • mind 后面接动名词 opening。
            """
        )
    }

    func testAnalyzeParagraphKeepsStructuredLayoutWhenModelOmitsUsage() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "{\\"points\\":[{\\"category\\":\\"语气逻辑\\",\\"quote\\":\\"I guess\\",\\"explanation\\":\\"用 guess 降低语气强度，让表达听起来不那么绝对。\\"}]}"} }]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let analysis = try await service.analyze(paragraph: "I guess we could try again.")

        XCTAssertEqual(
            analysis,
            """
            语气与逻辑
            • 原文：I guess
              作用：用 guess 降低语气强度，让表达听起来不那么绝对。
            """
        )
    }

    func testAnalyzeParagraphExtractsStructuredPointsWhenModelWrapsJsonWithHeading() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "语言观察\\n{\\"points\\":[{\\"category\\":\\"语法结构\\",\\"quote\\":\\"the root cause is a system glitch, not handwriting\\",\\"explanation\\":\\"使用 is A, not B 结构纠正错误假设，强调真正原因。\\",\\"usage\\":\\"指出原因时可用 The reason is X, not Y。\\"}]}"} }]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let analysis = try await service.analyze(paragraph: "The root cause is a system glitch, not handwriting.")

        XCTAssertEqual(
            analysis,
            """
            语法结构
            • 原文：the root cause is a system glitch, not handwriting
              作用：使用 is A, not B 结构纠正错误假设，强调真正原因。
              记忆：指出原因时可用 The reason is X, not Y。
            """
        )
    }

    func testAnalyzeParagraphExtractsCompletePointsFromIncompleteJsonResponse() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "{\\n  \\"points\\": [\\n    {\\n      \\"category\\": \\"表达/俚语\\",\\n      \\"quote\\": \\"no scrawling this time\\",\\n      \\"explanation\\": \\"用 no + 动名词轻松提醒自己不要重复坏习惯。\\",\\n      \\"usage\\": \\"可用 no rushing this time 表示这次别再赶。\\"\\n    },\\n    {\\n      \\"category\\": \\"语气逻辑\\",\\n      \\"quote\\": \\"Should we escala"} }]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) { _ in }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        let analysis = try await service.analyze(paragraph: "No scrawling this time.")

        XCTAssertEqual(
            analysis,
            """
            表达与俚语
            • 原文：no scrawling this time
              作用：用 no + 动名词轻松提醒自己不要重复坏习惯。
              记忆：可用 no rushing this time 表示这次别再赶。
            """
        )
        XCTAssertFalse(analysis.contains("\"points\""))
        XCTAssertFalse(analysis.contains("{"))
    }

    func testAnalyzeParagraphBuildsPromptForGrammarIdiomsAndSlangWithoutTranslation() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "{\\"points\\":[{\\"category\\":\\"语法结构\\",\\"quote\\":\\"Would you mind\\",\\"explanation\\":\\"用疑问句包装请求，语气更委婉。\\",\\"usage\\":\\"向别人提要求时，可用 Would you mind + doing。\\"}]}"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "moonshot-v1-8k"
        )
        let service = WordTranslatorService(config: config, session: session)

        _ = try await service.analyze(paragraph: "Would you mind opening the window?")

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let prompt = try XCTUnwrap(messages.first?["content"] as? String)

        XCTAssertTrue(prompt.contains("Would you mind opening the window?"))
        XCTAssertTrue(prompt.contains("grammar patterns, idioms, slang, implied tone"))
        XCTAssertTrue(prompt.contains("Do not translate the whole paragraph"))
        XCTAssertTrue(prompt.contains("Return valid JSON only"))
        XCTAssertTrue(prompt.contains("\"category\""))
        XCTAssertTrue(prompt.contains("\"quote\""))
        XCTAssertTrue(prompt.contains("\"explanation\""))
        XCTAssertTrue(prompt.contains("\"usage\""))
        XCTAssertTrue(prompt.contains("Do not use Markdown, numbering, or code fences"))
        XCTAssertEqual(object["max_tokens"] as? Int, 900)
    }
}
