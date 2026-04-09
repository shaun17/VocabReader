import XCTest
@testable import VocabReader

@MainActor
final class WordDetailViewModelTests: XCTestCase {
    func testLoadTranslationUsesTranslatorAutomatically() async {
        let translator = MockWordTranslatorService(result: .success("苹果"))
        let viewModel = WordDetailViewModel(
            word: VocabWord(id: "1", spelling: "apple"),
            translator: translator
        )

        await viewModel.loadTranslation()

        XCTAssertEqual(translator.receivedWords, ["apple"])
        XCTAssertEqual(viewModel.translation, "苹果")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadTranslationSurfacesTranslatorFailure() async {
        let translator = MockWordTranslatorService(result: .failure(LLMError.invalidResponse))
        let viewModel = WordDetailViewModel(
            word: VocabWord(id: "1", spelling: "apple"),
            translator: translator
        )

        await viewModel.loadTranslation()

        XCTAssertNil(viewModel.translation)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.error, "LLM 请求地址无效，请检查 Base URL")
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
