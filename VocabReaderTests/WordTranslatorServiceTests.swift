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

    func testAnalyzeParagraphReturnsAnalysisContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "这里的 would 用来让请求更委婉。"}}]
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

        XCTAssertEqual(analysis, "这里的 would 用来让请求更委婉。")
    }

    func testAnalyzeParagraphBuildsPromptForGrammarIdiomsAndSlangWithoutTranslation() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "解析"}}]
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
        XCTAssertEqual(object["max_tokens"] as? Int, 320)
    }
}
