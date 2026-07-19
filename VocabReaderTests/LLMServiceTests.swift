import XCTest
@testable import VocabReader

final class LLMServiceTests: XCTestCase {

    func testGenerateArticleReturnsContent() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Ephemeral Ideas\\n\\n<vocab id=\\"1\\">Ephemeral</vocab> ideas became <vocab id=\\"2\\">ubiquitous</vocab> in the town."}}]
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
          "choices": [{"message": {"role": "assistant", "content": "Lucky Plan\\n\\n<vocab id=\\"1\\">Serendipity</vocab> made the plan work."}}]
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

    /// Prompt 只给模型短标记 ID，避免真实词条 ID 太长导致模型截断标签。
    func testGenerateArticleUsesShortPromptMarkerIDsInsteadOfRawVocabularyIDs() async throws {
        var capturedRequest: URLRequest?
        let rawID = "voc-_X-2dtZKRf8cahiUUxNfB0SLDj0E0vyPwqFyoHobCggMFYWZQ0SUOcK5AMZr8ix"
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Customer Plan\\n\\nThe <vocab id=\\"w1\\">invitation</vocab> changed the meeting."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: rawID, spelling: "invitation")],
            scene: .dialogue,
            topic: .customer
        )

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("id=w1, word=invitation"))
        XCTAssertFalse(bodyString.contains(rawID))
        XCTAssertEqual(article.vocabularyOccurrences.first?.word.id, rawID)
    }

    /// 短标记 ID 必须能映射回真实词条，尤其是本地无法从词形推断的短语变形。
    func testGenerateArticleMapsShortPromptMarkerIDsBackToPhraseWords() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Flight Practice\\n\\nThe plane <vocab id=\\"w1\\">took off</vocab> after sunrise."}}]
        }
        """
        let session = QueueingMockSession(responses: [(Data(json.utf8), 200)])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: "raw-phrase-id-that-model-should-not-copy", spelling: "take off")],
            scene: .novel,
            topic: .general
        )

        XCTAssertEqual(article.content, "The plane took off after sunrise.")
        XCTAssertEqual(article.vocabularyOccurrences.first?.surfaceText, "took off")
        XCTAssertEqual(article.vocabularyOccurrences.first?.word.spelling, "take off")
        XCTAssertEqual(session.requests.count, 1)
    }

    func testPromptAllowsNaturalInflectedFormsInsteadOfForcingOriginalSpelling() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Customer Concerns\\n\\nThe customer raised several <vocab id=\\"1\\">concerns</vocab> during the meeting."}}]
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

    /// 大批次分段生成时，续写 Prompt 必须带上前文和同一篇文章约束。
    func testPromptAddsEnoughContextForLargeVocabularySections() async throws {
        var capturedRequest: URLRequest?
        let spellings = [
            "apple", "banana", "carrot", "dragon", "engine", "forest", "garden", "harbor", "island", "jacket",
            "kitten", "ladder", "market", "needle", "orange", "planet", "quartz", "river", "silver", "ticket",
            "umbrella", "valley", "window", "yellow", "zebra", "anchor", "bridge", "circle", "dinner", "energy"
        ]
        let vocabulary = spellings.enumerated().map { index, spelling in
            VocabWord(id: "\(index)", spelling: spelling)
        }
        let articleBody = vocabulary
            .map { "<vocab id=\\\"\($0.id)\\\">\($0.spelling)</vocab>" }
            .joined(separator: " ")
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
        XCTAssertTrue(bodyString.contains("Continue the same article with Section 3 of 3"))
        XCTAssertTrue(bodyString.contains("This is one article split into 3 connected generation steps"))
        XCTAssertTrue(bodyString.contains("The full article will cover 30 target vocabulary items"))
        XCTAssertTrue(bodyString.contains("Write around 70-110 English words for this closing section"))
        XCTAssertTrue(bodyString.contains("Do not restart, summarize, or switch topics between sections"))
        XCTAssertTrue(bodyString.contains("Previous article content:"))
        XCTAssertTrue(bodyString.contains("Do not write isolated example sentences"))
        XCTAssertTrue(bodyString.contains("Do not use Markdown emphasis"))
        XCTAssertTrue(bodyString.contains("Only the CURRENT SECTION items are coverage requirements"))
    }

    /// 30 词批次要拆成同一篇文章的连续段落生成，避免一次性塞给模型后整批漏词。
    func testGenerateArticleUsesLinkedSectionsForThirtyWordBatches() async throws {
        let spellings = [
            "apple", "banana", "carrot", "dragon", "engine", "forest", "garden", "harbor", "island", "jacket",
            "kitten", "ladder", "market", "needle", "orange", "planet", "quartz", "river", "silver", "ticket",
            "umbrella", "valley", "window", "yellow", "zebra", "anchor", "bridge", "circle", "dinner", "energy"
        ]
        let words = spellings.enumerated().map { index, spelling in
            VocabWord(id: "\(index + 1)", spelling: spelling)
        }
        let responses = [
            "Linked Case - Section 1\\n\\nA: \(taggedWords(words[0..<10])) opened the same problem.",
            "B: \(taggedWords(words[10..<20])) made the decision harder.",
            "A: \(taggedWords(words[20..<30])) finally shaped the outcome."
        ].map { content in
            """
            {
              "choices": [{"message": {"role": "assistant", "content": "\(content)"}}]
            }
            """
        }
        let session = QueueingMockSession(responses: responses.map { (Data($0.utf8), 200) })
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(words: words, scene: .dialogue, topic: .general)

        XCTAssertEqual(article.title, "Linked Case")
        XCTAssertEqual(article.vocabularyOccurrences.count, 30)
        XCTAssertEqual(session.requests.count, 3)

        let firstPrompt = try requestPrompt(session.requests[0])
        XCTAssertTrue(firstPrompt.contains("Section 1 of 3"))
        XCTAssertTrue(firstPrompt.contains("word=apple"))
        XCTAssertTrue(firstPrompt.contains("Full-article vocabulary map"))
        XCTAssertTrue(firstPrompt.contains("word=kitten"))
        XCTAssertTrue(firstPrompt.contains("word=umbrella"))

        let secondPrompt = try requestPrompt(session.requests[1])
        XCTAssertTrue(secondPrompt.contains("Continue the same article"))
        XCTAssertTrue(secondPrompt.contains("A: apple, banana"))
        XCTAssertTrue(secondPrompt.contains("word=kitten"))
        XCTAssertTrue(secondPrompt.contains("word=umbrella"))
    }

    /// 分段合并后要保留每段已解析出的短语命中，不能重新扫正文导致变形短语丢失。
    func testGenerateArticleKeepsMarkedPhraseOccurrencesWhenMergingSections() async throws {
        let words = [VocabWord(id: "phrase-raw-id", spelling: "take off")] +
            (2...21).map { VocabWord(id: "raw-\($0)", spelling: "word\($0)") }
        let responses = [
            "Linked Flight\\n\\nThe plane <vocab id=\\\"w1\\\">took off</vocab> while \(taggedAliasWords(words[1..<10], startIndex: 2)) shaped the same plan.",
            "Then \(taggedAliasWords(words[10..<20], startIndex: 11)) kept the team aligned.",
            "Finally <vocab id=\\\"w21\\\">word21</vocab> closed the same decision."
        ].map { content in
            """
            {
              "choices": [{"message": {"role": "assistant", "content": "\(content)"}}]
            }
            """
        }
        let session = QueueingMockSession(responses: responses.map { (Data($0.utf8), 200) })
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(words: words, scene: .novel, topic: .general)

        XCTAssertEqual(article.vocabularyOccurrences.count, 21)
        XCTAssertEqual(article.vocabularyOccurrences.first?.word.spelling, "take off")
        XCTAssertEqual(article.vocabularyOccurrences.first?.surfaceText, "took off")
        XCTAssertFalse(article.content.contains("To keep the same situation moving"))
        XCTAssertEqual(session.requests.count, 3)
    }

    /// 分段缺词重试只能重写当前段，不能让模型返回整篇正文后再次拼进前文。
    func testSectionRetryPromptRequestsOnlyTheCorrectedCurrentSection() async throws {
        let words = (1...21).map { VocabWord(id: "raw-\($0)", spelling: "word\($0)") }
        let responses = [
            "Linked Plan\\n\\n\(taggedAliasWords(words[0..<9], startIndex: 1))",
            "Linked Plan\\n\\n\(taggedAliasWords(words[0..<10], startIndex: 1))",
            taggedAliasWords(words[10..<20], startIndex: 11),
            "<vocab id=\\\"w21\\\">word21</vocab>"
        ].map { content in
            """
            {
              "choices": [{"message": {"role": "assistant", "content": "\(content)"}}]
            }
            """
        }
        let session = QueueingMockSession(responses: responses.map { (Data($0.utf8), 200) })
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: words, scene: .novel, topic: .general)

        let retryPrompt = try requestPrompt(session.requests[1])
        XCTAssertTrue(retryPrompt.contains("Return the full corrected section"))
        XCTAssertTrue(retryPrompt.contains("Do not repeat previous article content"))
        XCTAssertFalse(retryPrompt.contains("Return the full corrected article"))
    }

    /// 确保 Prompt 把短文定义成一条连续主线，而不是一组互不相干的例句。
    func testPromptRequiresSingleCoherentThroughLineAcrossTheWholeArticle() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Workshop Plan\\n\\nThe <vocab id=\\"1\\">mentor</vocab> explained why the quiet <vocab id=\\"2\\">river</vocab> mattered to the design."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(
            words: [
                VocabWord(id: "1", spelling: "mentor"),
                VocabWord(id: "2", spelling: "river")
            ],
            scene: .science,
            topic: .general
        )

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("Use one central through-line from beginning to end"))
        XCTAssertTrue(bodyString.contains("Every sentence, paragraph, or dialogue turn must follow from the previous one"))
        XCTAssertTrue(bodyString.contains("Do not write isolated example sentences"))
    }

    /// 学习短文必须优先使用真实交流中常见、自然的现代英语，不能为了塞词写生硬句式。
    func testPromptRequiresCommonNaturalEnglishAndIdiomaticWordUse() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "A Clear Choice\\n\\nThe <vocab id=\\"w1\\">choice</vocab> felt natural in the conversation."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(
            words: [VocabWord(id: "1", spelling: "choice")],
            scene: .novel,
            topic: .general
        )

        let prompt = try requestPrompt(XCTUnwrap(capturedRequest))
        XCTAssertTrue(prompt.contains("common in contemporary everyday English"))
        XCTAssertTrue(prompt.contains("natural collocations and sentence patterns"))
        XCTAssertTrue(prompt.contains("Never distort the meaning or grammar just to include a target word"))
    }

    /// 确保对话不是一问一答或一方附和，而是双方都推动同一个场景。
    func testDialoguePromptRequiresBothSpeakersToDriveTheSameConversation() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Team Talk\\n\\nA: The <vocab id=\\"1\\">feedback</vocab> changed our plan."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(words: [VocabWord(id: "1", spelling: "feedback")], scene: .dialogue, topic: .customer)

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("Both speakers must actively drive the conversation"))
        XCTAssertTrue(bodyString.contains("Do not make one speaker only ask questions while the other only agrees"))
        XCTAssertTrue(bodyString.contains("Keep the conversation on the same topic; do not abruptly switch subjects"))
    }

    func testGenerateArticleRetriesWhenResponseMissesRequiredWords() async throws {
        let firstJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Draft\\n\\nThe <vocab id=\\"1\\">apple</vocab> stayed on the desk."}}]
        }
        """
        let secondJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Complete Draft\\n\\nThe <vocab id=\\"1\\">apple</vocab> stayed beside the <vocab id=\\"2\\">river</vocab>."}}]
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

    /// 缺词重试必须带上上一版正文，避免模型每次从零开始又丢掉已经覆盖的词。
    func testGenerateArticleRetryPromptIncludesPreviousDraftForRepair() async throws {
        let firstJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Draft\\n\\nThe <vocab id=\\"1\\">apple</vocab> stayed on the desk."}}]
        }
        """
        let secondJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Complete Draft\\n\\nThe <vocab id=\\"1\\">apple</vocab> stayed beside the <vocab id=\\"2\\">river</vocab>."}}]
        }
        """
        let session = QueueingMockSession(responses: [
            (Data(firstJSON.utf8), 200),
            (Data(secondJSON.utf8), 200)
        ])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        _ = try await service.generateArticle(
            words: [
                VocabWord(id: "1", spelling: "apple"),
                VocabWord(id: "2", spelling: "river")
            ],
            scene: .novel,
            topic: .general
        )

        let secondBody = try XCTUnwrap(session.requests.last?.httpBody)
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let messages = try XCTUnwrap(secondObject["messages"] as? [[String: Any]])
        let retryPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(retryPrompt.contains("Revise this previous draft"))
        XCTAssertTrue(retryPrompt.contains("The apple stayed on the desk."))
    }

    /// 大批次也必须基于同一篇草稿修订，避免拆成互不相关的片段后再拼接。
    func testGenerateArticleRetriesSameDraftForLargeBatchesWhenWordsAreMissing() async throws {
        let words = (1...6).map { VocabWord(id: "\($0)", spelling: "word\($0)") }
        let firstJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Draft\\n\\n<vocab id=\\"1\\">word1</vocab> leads the plan."}}]
        }
        """
        let secondBody = words
            .map { "<vocab id=\\\"\($0.id)\\\">\($0.spelling)</vocab>" }
            .joined(separator: " ")
        let secondJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Complete Draft\\n\\n\(secondBody)"}}]
        }
        """
        let session = QueueingMockSession(responses: [
            (Data(firstJSON.utf8), 200),
            (Data(secondJSON.utf8), 200)
        ])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(words: words, scene: .novel, topic: .general)

        XCTAssertEqual(article.title, "Complete Draft")
        XCTAssertEqual(session.requests.count, 2)
        let secondRequestBody = try XCTUnwrap(session.requests.last?.httpBody)
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: secondRequestBody) as? [String: Any])
        let messages = try XCTUnwrap(secondObject["messages"] as? [[String: Any]])
        let retryPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(retryPrompt.contains("Revise this previous draft"))
        XCTAssertTrue(retryPrompt.contains("word1 leads the plan"))
    }

    func testGenerateArticleAcceptsInflectedTargetWordForms() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Customer Concerns\\n\\nThe customer raised several <vocab id=\\"1\\">concerns</vocab> during the meeting."}}]
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

    func testGenerateArticleFallsBackToLocalCoverageWhenVocabularyMarkersAreMissing() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Kitchen Draft\\n\\nThe humble cook chopped onions beside the river."}}]
        }
        """
        let responses = Array(repeating: (Data(json.utf8), 200), count: 3)
        let session = QueueingMockSession(responses: responses)
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [
                VocabWord(id: "1", spelling: "humble"),
                VocabWord(id: "2", spelling: "chop"),
                VocabWord(id: "3", spelling: "river")
            ],
            scene: .novel,
            topic: .general
        )

        XCTAssertEqual(article.content, "The humble cook chopped onions beside the river.")
        XCTAssertEqual(article.vocabularyOccurrences.map(\.surfaceText), ["humble", "chopped", "river"])
        XCTAssertEqual(article.vocabularyOccurrences.map(\.word.spelling), ["humble", "chop", "river"])
        XCTAssertEqual(session.requests.count, 1)
    }

    func testGenerateArticleTreatsDialogueOpeningLineAsBodyWhenTitleIsMissing() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "A: Your handling felt like a <vocab id=\\"1\\">pistol</vocab> -- too quick to draw conclusions.\\nB: I should have been more <vocab id=\\"2\\">humble</vocab> and listened first.\\nA: We had to <vocab id=\\"3\\">chop</vocab> the original plan after the customer's pushback."}}]
        }
        """
        let responses = Array(repeating: (Data(json.utf8), 200), count: 3)
        let session = QueueingMockSession(responses: responses)
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [
                VocabWord(id: "1", spelling: "pistol"),
                VocabWord(id: "2", spelling: "humble"),
                VocabWord(id: "3", spelling: "chop")
            ],
            scene: .dialogue,
            topic: .customer
        )

        XCTAssertEqual(article.title, "")
        XCTAssertFalse(article.content.contains("<vocab"))
        XCTAssertTrue(article.content.hasPrefix("A: Your handling felt like a pistol"))
        XCTAssertEqual(article.vocabularyOccurrences.map(\.surfaceText), ["pistol", "humble", "chop"])
        XCTAssertEqual(session.requests.count, 1)
    }

    func testGenerateArticleStripsVocabularyMarkersFromTitleWithoutCountingTitleCoverage() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "The <vocab id=\\"1\\">pistol</vocab> Review\\n\\nThe client described the decision as a <vocab id=\\"1\\">pistol</vocab> pointed at the schedule."}}]
        }
        """
        let session = QueueingMockSession(responses: [(Data(json.utf8), 200)])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: "1", spelling: "pistol")],
            scene: .novel,
            topic: .customer
        )

        XCTAssertEqual(article.title, "The pistol Review")
        XCTAssertEqual(article.content, "The client described the decision as a pistol pointed at the schedule.")
        XCTAssertEqual(article.vocabularyOccurrences.map(\.surfaceText), ["pistol"])
        XCTAssertEqual(article.vocabularyOccurrences.first?.range, NSRange(location: 39, length: 6))
    }

    func testGenerateArticleFallsBackToExactPhraseCoverageWhenVocabularyMarkerIsMissing() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Flight Draft\\n\\nThe plane will take off after sunrise."}}]
        }
        """
        let responses = Array(repeating: (Data(json.utf8), 200), count: 3)
        let session = QueueingMockSession(responses: responses)
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: "phrase-1", spelling: "take off")],
            scene: .novel,
            topic: .general
        )

        XCTAssertEqual(article.content, "The plane will take off after sunrise.")
        XCTAssertEqual(article.vocabularyOccurrences.map(\.surfaceText), ["take off"])
        XCTAssertEqual(article.vocabularyOccurrences.first?.word.spelling, "take off")
        XCTAssertEqual(session.requests.count, 1)
    }

    func testGenerateArticleUsesVocabularyMarkersForPhraseTargets() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Flight Practice\\n\\nThe plane <vocab id=\\"phrase-1\\">took off</vocab> after sunrise."}}]
        }
        """
        let session = QueueingMockSession(responses: [(Data(json.utf8), 200)])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: "phrase-1", spelling: "take off")],
            scene: .novel,
            topic: .general
        )

        XCTAssertEqual(article.content, "The plane took off after sunrise.")
        XCTAssertEqual(article.vocabularyOccurrences.count, 1)
        XCTAssertEqual(article.vocabularyOccurrences.first?.word.spelling, "take off")
        XCTAssertEqual(article.vocabularyOccurrences.first?.surfaceText, "took off")
        XCTAssertEqual(article.vocabularyOccurrences.first?.range, NSRange(location: 10, length: 8))
    }

    func testGenerateArticleRetriesWhenVocabularyMarkerMissesPhraseTarget() async throws {
        let firstJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Draft\\n\\nThe plane took off after sunrise."}}]
        }
        """
        let secondJSON = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Fixed Draft\\n\\nThe plane <vocab id=\\"phrase-1\\">took off</vocab> after sunrise."}}]
        }
        """
        let session = QueueingMockSession(responses: [
            (Data(firstJSON.utf8), 200),
            (Data(secondJSON.utf8), 200)
        ])
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)

        let article = try await service.generateArticle(
            words: [VocabWord(id: "phrase-1", spelling: "take off")],
            scene: .novel,
            topic: .general
        )

        XCTAssertEqual(article.title, "Fixed Draft")
        XCTAssertEqual(article.content, "The plane took off after sunrise.")
        XCTAssertEqual(session.requests.count, 2)

        let secondBody = try XCTUnwrap(session.requests.last?.httpBody)
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let messages = try XCTUnwrap(secondObject["messages"] as? [[String: Any]])
        let retryPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(retryPrompt.contains("Missing vocabulary words from the previous draft: take off"))
    }

    /// 连续缺词时宁可明确失败，也不能在正文末尾追加与上下文无关的模板句硬塞词汇。
    func testGenerateArticleRejectsDisconnectedLocalCoverageRepairAfterRetryLimit() async throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Draft\\n\\nThis draft does not contain the requested vocabulary."}}]
        }
        """
        let responses = Array(repeating: (Data(json.utf8), 200), count: 3)
        let session = QueueingMockSession(responses: responses)
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)
        let spellings = ["apple", "river", "cliff", "observe", "variety", "deficit"]
        let words = spellings.enumerated().map { index, spelling in
            VocabWord(id: "\(index + 1)", spelling: spelling)
        }

        do {
            _ = try await service.generateArticle(words: words, scene: .novel, topic: .general)
            XCTFail("连续缺词后不应返回本地模板补句拼成的文章")
        } catch LLMError.missingVocabularyWords(let missingWords) {
            XCTAssertEqual(missingWords, spellings)
        }
        XCTAssertEqual(session.requests.count, 3)
    }

    /// 后续重试偶发退化时，最终错误必须报告覆盖率最高草稿的缺词，不能用最后一版覆盖真实进展。
    func testGenerateArticleReportsMissingWordsFromBestRetryDraft() async throws {
        let responses = [
            "Draft One\\n\\nThe apple stayed on the desk.",
            "Draft Two\\n\\nThe apple stood beside the river.",
            "Draft Three\\n\\nThe desk was empty."
        ].map { content in
            """
            {
              "choices": [{"message": {"role": "assistant", "content": "\(content)"}}]
            }
            """
        }
        let session = QueueingMockSession(
            responses: responses.map { (Data($0.utf8), 200) }
        )
        let config = LLMConfig(apiKey: "key", baseURL: "https://api.example.com/v1", model: "gpt-4o")
        let service = LLMService(config: config, session: session)
        let words = [
            VocabWord(id: "1", spelling: "apple"),
            VocabWord(id: "2", spelling: "river"),
            VocabWord(id: "3", spelling: "cliff")
        ]

        do {
            _ = try await service.generateArticle(words: words, scene: .novel, topic: .general)
            XCTFail("三次草稿都缺词时应明确失败")
        } catch LLMError.missingVocabularyWords(let missingWords) {
            XCTAssertEqual(missingWords, ["cliff"])
        } catch {
            XCTFail("收到非预期错误：\(error)")
        }
    }

    func testGenerateArticleCapsRequestTimeoutForInteractiveGeneration() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Fresh Fruit\\n\\nThe <vocab id=\\"1\\">apple</vocab> stayed fresh."}}]
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
        XCTAssertEqual(timeoutInterval, 45, accuracy: 0.1)
    }

    func testGenerateArticleRequestsDisabledThinkingAndBoundedOutput() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Fresh Fruit\\n\\nThe <vocab id=\\"1\\">apple</vocab> stayed fresh."}}]
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
        XCTAssertEqual(object["max_tokens"] as? Int, 1600)
    }

    func testConnectionAllowsEnoughOutputTokensForReasoningModels() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "OK", "reasoning_content": "The user asked for an OK response."}}]
        }
        """
        let session = CapturingMockSession(data: Data(json.utf8), statusCode: 200) {
            capturedRequest = $0
        }
        let config = LLMConfig(
            apiKey: "key",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-pro"
        )
        let service = LLMService(config: config, session: session)

        try await service.testConnection()

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let maxTokens = try XCTUnwrap(object["max_tokens"] as? Int)
        XCTAssertGreaterThanOrEqual(maxTokens, 64)
    }

    func testDialoguePromptRequiresSpeakerFormatting() async throws {
        var capturedRequest: URLRequest?
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "Shared Snack\\n\\nA: I brought an <vocab id=\\"1\\">apple</vocab>."}}]
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
          "choices": [{"message": {"role": "assistant", "content": "Team Talk\\n\\nA: Thank you for the <vocab id=\\"1\\">feedback</vocab>."}}]
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
          "choices": [{"message": {"role": "assistant", "content": "Rolling Fruit\\n\\nThe <vocab id=\\"1\\">apple</vocab> rolled across the table."}}]
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
          "choices": [{"message": {"role": "assistant", "content": "Morning Care\\n\\nThe <vocab id=\\"1\\">clinic</vocab> opened early."}}]
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
          "choices": [{"message": {"role": "assistant", "content": "Client Plan\\n\\nThe <vocab id=\\"1\\">proposal</vocab> needed clearer timing."}}]
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
          "choices": [{"message": {"role": "assistant", "content": "River Snack\\n\\nA: The <vocab id=\\"1\\">apple</vocab> fell near the <vocab id=\\"2\\">river</vocab>."}}]
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

private extension LLMServiceTests {
    /// 生成测试用的内联词汇标记，模拟 LLM 已经正确标注目标词。
    func taggedWords(_ words: ArraySlice<VocabWord>) -> String {
        words.map { word in
            #"<vocab id=\"\#(word.id)\">\#(word.spelling)</vocab>"#
        }
        .joined(separator: ", ")
    }

    /// 生成使用 w1/w2 这类短标记 ID 的测试文本。
    func taggedAliasWords(_ words: ArraySlice<VocabWord>, startIndex: Int) -> String {
        words.enumerated().map { offset, word in
            #"<vocab id=\"w\#(startIndex + offset)\">\#(word.spelling)</vocab>"#
        }
        .joined(separator: ", ")
    }

    /// 从 mock 请求体里取出最终发送给模型的 Prompt。
    func requestPrompt(_ request: URLRequest) throws -> String {
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        return try XCTUnwrap(messages.first?["content"] as? String)
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
