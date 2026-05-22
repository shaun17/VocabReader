import XCTest
@testable import VocabReader

final class LLMServiceTests: XCTestCase {

    func testGenerateArticleReturnsContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Ephemeral Ideas\\n\\nEphemeral ideas became ubiquitous in the town."}}]
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

        let article = try await service.generateArticle(words: words, scene: .novel, topic: .general)

        XCTAssertEqual(article.title, "Ephemeral Ideas")
        XCTAssertEqual(article.content, "Ephemeral ideas became ubiquitous in the town.")
        XCTAssertEqual(article.scene, .novel)
        XCTAssertEqual(article.topic, .general)
        XCTAssertEqual(article.targetWords.count, 2)
    }

    func testGenerateArticleThrowsOnHTTPError() async {
        let session = MockURLSession(data: Data(), statusCode: 429)
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        do {
            _ = try await service.generateArticle(words: [], scene: .science, topic: .general)
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
          "choices": [{"message": {"role": "assistant", "content": "Serendipity made the plan work."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)
        let words = [VocabWord(id: "1", spelling: "serendipity")]

        _ = try await service.generateArticle(words: words, scene: .novel, topic: .general)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("serendipity"), "Prompt must include word spelling")
    }

    func testPromptAllowsNaturalInflectedFormsInsteadOfForcingOriginalSpelling() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Customer Concerns\\n\\nThe customer raised several concerns during the meeting."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(
            words: [VocabWord(id: "1", spelling: "concern")],
            scene: .dialogue,
            topic: .customer
        )

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("original spelling or a natural inflected form"))
        XCTAssertFalse(bodyString.contains("Each word must appear in its original spelling"))
    }

    func testPromptAddsEnoughContextForLargeVocabularyBatches() async throws {
        var capturedRequest: URLRequest?
        let spellings = [
            "apple", "banana", "carrot", "dragon", "engine", "forest", "garden", "harbor", "island", "jacket",
            "kitten", "ladder", "market", "needle", "orange", "planet", "quartz", "river", "silver", "ticket",
            "umbrella", "valley", "window", "yellow", "zebra", "anchor", "bridge", "circle", "dinner", "energy"
        ]
        let vocabulary = spellings.enumerated().map { index, spelling in
            VocabWord(id: "\(index)", spelling: spelling)
        }
        let articleBody = vocabulary.map(\.spelling).joined(separator: " ")
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Practice Scene\\n\\n\(articleBody)"}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: vocabulary, scene: .dialogue, topic: .general)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("Write around 220-320 English words"))
        XCTAssertTrue(bodyString.contains("Spread the vocabulary across the whole article"))
        XCTAssertTrue(bodyString.contains("Do not turn the article into a vocabulary checklist"))
    }

    func testGenerateArticleRetriesWhenResponseMissesRequiredWords() async throws {
        let firstJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Draft\\n\\nThe apple stayed on the desk."}}]
        }
        """
        let secondJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Complete Draft\\n\\nThe apple stayed beside the river."}}]
        }
        """
        let session = QueueingMockSession(responses: [
            (Data(firstJSON.utf8), 200),
            (Data(secondJSON.utf8), 200)
        ])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)
        let words = [
            VocabWord(id: "1", spelling: "apple"),
            VocabWord(id: "2", spelling: "river")
        ]

        let article = try await service.generateArticle(words: words, scene: .novel, topic: .general)

        XCTAssertEqual(article.title, "Complete Draft")
        XCTAssertEqual(article.content, "The apple stayed beside the river.")
        XCTAssertEqual(session.requests.count, 2)

        let secondBody = try XCTUnwrap(session.requests.last?.httpBody)
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let messages = try XCTUnwrap(secondObject["messages"] as? [[String: Any]])
        let retryPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(retryPrompt.contains("Missing vocabulary words from the previous draft: river"))
    }

    func testGenerateArticleAcceptsInflectedTargetWordForms() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Customer Concerns\\n\\nThe customer raised several concerns during the meeting."}}]
        }
        """
        let session = QueueingMockSession(responses: [(Data(json.utf8), 200)])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: "1", spelling: "concern")],
            scene: .dialogue,
            topic: .customer
        )

        XCTAssertEqual(article.content, "The customer raised several concerns during the meeting.")
        XCTAssertEqual(session.requests.count, 1)
    }

    func testGenerateArticleConfiguresRequestTimeout() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "The apple stayed fresh."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.moonshot.cn/v1",
            model: "kimi-k2.5"
        )
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "apple")], scene: .novel, topic: .general)

        let timeoutInterval = try XCTUnwrap(capturedRequest?.timeoutInterval)
        XCTAssertEqual(timeoutInterval, 180, accuracy: 0.1)
    }

    func testGenerateArticleRequestsDisabledThinkingAndBoundedOutput() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "The apple stayed fresh."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.moonshot.cn/v1",
            model: "kimi-k2.5"
        )
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "apple")], scene: .novel, topic: .general)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertEqual(object["max_tokens"] as? Int, 900)
    }

    func testDialoguePromptRequiresSpeakerFormatting() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "A: I brought an apple."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "apple")], scene: .dialogue, topic: .general)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("Every spoken turn must start on a new line"))
        XCTAssertTrue(bodyString.contains("Do not collapse the dialogue into large prose paragraphs"))
    }

    func testDialoguePromptRequiresPracticalConversationSkillsAndEmotionalDepth() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "A: Thank you for the feedback."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "feedback")], scene: .dialogue, topic: .general)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("Build the dialogue around one realistic situation"))
        XCTAssertTrue(bodyString.contains("Each speaker should have a clear goal, emotion, and response strategy"))
        XCTAssertTrue(bodyString.contains("Include reusable conversation skills"))
        XCTAssertTrue(bodyString.contains("Avoid shallow one-question-one-answer exchanges"))
    }

    func testNovelPromptRequiresParagraphsAndAccurateGrammar() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "The apple rolled across the table."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "apple")], scene: .novel, topic: .general)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("Use 3-5 short narrative paragraphs separated by blank lines"))
        XCTAssertTrue(bodyString.contains("Grammar, punctuation, and word usage must be accurate and natural"))
        XCTAssertTrue(bodyString.contains("The article as a whole must include ALL of the listed vocabulary words"))
    }

    func testMedicalTopicPromptAddsStrictFactConstraint() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "The clinic opened early."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "clinic")], scene: .science, topic: .medical)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("general medical knowledge and health education"))
        XCTAssertTrue(bodyString.contains("Do not invent precise statistics"))
        XCTAssertTrue(bodyString.contains("do not give diagnosis, treatment plans, or urgent medical advice"))
    }

    func testCustomerTopicPromptAddsBusinessConstraint() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "The proposal needed clearer timing."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "proposal")], scene: .dialogue, topic: .customer)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("customer cases, business collaboration, and workplace communication"))
        XCTAssertTrue(bodyString.contains("Avoid fictional customer names, contract details, business metrics, testimonials, or delivery commitments"))
    }

    func testDialoguePromptDoesNotRequireEveryBlockToRepeatAllTargetWords() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "A: The apple fell near the river."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(
            words: [
                VocabWord(id: "1", spelling: "apple"),
                VocabWord(id: "2", spelling: "river")
            ],
            scene: .dialogue,
            topic: .general
        )

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("The article as a whole must include ALL of the listed vocabulary words"))
        XCTAssertFalse(bodyString.contains("Every paragraph must include ALL of the listed vocabulary words"))
        XCTAssertFalse(bodyString.contains("If the format is dialogue, treat each dialogue block as a paragraph"))
    }

    func testArticleScenesDoNotContainNews() {
        XCTAssertEqual(Set(ArticleScene.allCases), Set([.dialogue, .science, .novel]))
    }

    func testArticleTopicsCoverStrictFactThemes() {
        XCTAssertEqual(Set(ArticleTopic.allCases), Set([.general, .technology, .medical, .ai, .customer]))
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

final class QueueingMockSession: URLSessionProtocol {
    private var responses: [(data: Data, statusCode: Int)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses.map { (data: $0.0, statusCode: $0.1) }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response: (data: Data, statusCode: Int)
        if responses.isEmpty {
            response = (Data(), 500)
        } else {
            response = responses.removeFirst()
        }
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response.data, httpResponse)
    }
}
