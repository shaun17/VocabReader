import XCTest
@testable import VocabReader

@MainActor
final class WordDetailViewModelTests: XCTestCase {
    func testPresentUsesTranslatorAutomatically() async {
        let translator = MockWordTranslatorService(result: .success("苹果"))
        let word = VocabWord(id: "1", spelling: "apple")
        let viewModel = WordDetailViewModel(translator: translator)

        await viewModel.present(word: word)

        XCTAssertEqual(translator.receivedWords, ["apple"])
        XCTAssertEqual(viewModel.word?.spelling, "apple")
        XCTAssertEqual(viewModel.translation, "苹果")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testPresentSurfacesTranslatorFailure() async {
        let translator = MockWordTranslatorService(result: .failure(LLMError.invalidResponse))
        let word = VocabWord(id: "1", spelling: "apple")
        let viewModel = WordDetailViewModel(translator: translator)

        await viewModel.present(word: word)

        XCTAssertEqual(viewModel.word?.spelling, "apple")
        XCTAssertNil(viewModel.translation)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.error, "LLM 请求地址无效，请检查 Base URL")
    }

    func testDismissClearsPresentedWordAndTranslationState() async {
        let translator = MockWordTranslatorService(result: .success("苹果"))
        let word = VocabWord(id: "1", spelling: "apple")
        let viewModel = WordDetailViewModel(translator: translator)

        await viewModel.present(word: word)
        viewModel.dismiss()

        XCTAssertNil(viewModel.word)
        XCTAssertNil(viewModel.translation)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testPresentIgnoresStaleTranslationResponses() async {
        let translator = ControlledWordTranslatorService()
        let viewModel = WordDetailViewModel(translator: translator)

        let firstTask = Task {
            await viewModel.present(word: VocabWord(id: "1", spelling: "apple"))
        }

        await translator.waitUntilRequestArrives(for: "apple")

        let secondTask = Task {
            await viewModel.present(word: VocabWord(id: "2", spelling: "banana"))
        }

        await translator.waitUntilRequestArrives(for: "banana")
        await translator.resume(word: "banana", with: .success("香蕉"))
        await secondTask.value
        await translator.resume(word: "apple", with: .success("苹果"))
        await firstTask.value

        XCTAssertEqual(viewModel.word?.spelling, "banana")
        XCTAssertEqual(viewModel.translation, "香蕉")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }
}

private final class MockWordTranslatorService: WordTranslatorServiceProtocol {
    var receivedWords: [String] = []
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func translate(word: String) async throws -> String {
        receivedWords.append(word)
        return try result.get()
    }
}

private actor ControlledWordTranslatorService: WordTranslatorServiceProtocol {
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var resumptions: [String: CheckedContinuation<String, Error>] = [:]

    func translate(word: String) async throws -> String {
        waiters[word]?.resume()
        waiters[word] = nil

        return try await withCheckedThrowingContinuation { continuation in
            resumptions[word] = continuation
        }
    }

    func waitUntilRequestArrives(for word: String) async {
        if resumptions[word] != nil {
            return
        }

        await withCheckedContinuation { continuation in
            waiters[word] = continuation
        }
    }

    func resume(word: String, with result: Result<String, Error>) {
        guard let continuation = resumptions[word] else { return }
        resumptions[word] = nil

        switch result {
        case .success(let translation):
            continuation.resume(returning: translation)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
