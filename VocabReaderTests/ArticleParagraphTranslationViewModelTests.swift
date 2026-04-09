import XCTest
@testable import VocabReader

@MainActor
final class ArticleParagraphTranslationViewModelTests: XCTestCase {
    func testTranslateLoadsParagraphTranslationAndExpandsIt() async {
        let translator = MockParagraphTranslator(result: .success("这是本段译文。"))
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "This is a paragraph.",
            translator: translator
        )

        await viewModel.didTapTranslateButton()

        XCTAssertEqual(translator.receivedParagraphs, ["This is a paragraph."])
        XCTAssertEqual(viewModel.translation, "这是本段译文。")
        XCTAssertTrue(viewModel.isExpanded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testTranslateButtonTogglesExpansionAfterTranslationIsLoaded() async {
        let translator = MockParagraphTranslator(result: .success("这是本段译文。"))
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "This is a paragraph.",
            translator: translator
        )

        await viewModel.didTapTranslateButton()
        await viewModel.didTapTranslateButton()

        XCTAssertEqual(translator.receivedParagraphs, ["This is a paragraph."])
        XCTAssertFalse(viewModel.isExpanded)
        XCTAssertEqual(viewModel.translation, "这是本段译文。")
    }

    func testTranslateSurfacesErrorAndDoesNotExpand() async {
        let translator = MockParagraphTranslator(result: .failure(LLMError.invalidResponse))
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "This is a paragraph.",
            translator: translator
        )

        await viewModel.didTapTranslateButton()

        XCTAssertNil(viewModel.translation)
        XCTAssertFalse(viewModel.isExpanded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.error, "LLM 请求地址无效，请检查 Base URL")
    }
}

private final class MockParagraphTranslator: ArticleParagraphTranslatorProtocol {
    var receivedParagraphs: [String] = []
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func translate(paragraph: String) async throws -> String {
        receivedParagraphs.append(paragraph)
        return try result.get()
    }
}
