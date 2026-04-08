import XCTest
@testable import VocabReader

final class LLMServiceTests: XCTestCase {

    func testGenerateArticleReturnsContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Once upon a time..."}}]
        }
        """
        let session = MockURLSession(data: Data(json.utf8), statusCode: 200)
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.example.com/v1",
            model: "gpt-4o"
        )
        let service = LLMService(config: config, session: session)
        let words = [
            VocabWord(id: "1", spelling: "ephemeral"),
            VocabWord(id: "2", spelling: "ubiquitous")
        ]

        let article = try await service.generateArticle(words: words, scene: .story)

        XCTAssertEqual(article.content, "Once upon a time...")
        XCTAssertEqual(article.scene, .story)
        XCTAssertEqual(article.targetWords.count, 2)
    }

    func testGenerateArticleThrowsOnHTTPError() async {
        let session = MockURLSession(data: Data(), statusCode: 429)
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        do {
            _ = try await service.generateArticle(words: [], scene: .news)
            XCTFail("Expected error")
        } catch LLMError.httpError(let code, _) {
            XCTAssertEqual(code, 429)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testPromptIncludesAllWords() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "text"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)
        let words = [VocabWord(id: "1", spelling: "serendipity")]

        _ = try await service.generateArticle(words: words, scene: .story)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("serendipity"), "Prompt must include word spelling")
    }
}

// CapturingMockSession captures the request for inspection
final class CapturingMockSession: URLSessionProtocol {
    let data: Data
    let statusCode: Int
    let onRequest: (URLRequest) -> Void

    init(data: Data, statusCode: Int, onRequest: @escaping (URLRequest) -> Void) {
        self.data = data
        self.statusCode = statusCode
        self.onRequest = onRequest
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        onRequest(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
