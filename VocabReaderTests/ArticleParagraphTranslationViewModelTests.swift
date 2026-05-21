import XCTest
@testable import VocabReader

@MainActor
final class ArticleParagraphTranslationViewModelTests: XCTestCase {
    func testTranslateLoadsParagraphTranslationAndExpandsIt() async {
        let translator = MockParagraphAssistant(translationResult: .success("这是本段译文。"))
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
        let translator = MockParagraphAssistant(translationResult: .success("这是本段译文。"))
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
        let translator = MockParagraphAssistant(translationResult: .failure(LLMError.invalidResponse))
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

    func testAnalyzeLoadsParagraphAnalysisAndExpandsIt() async {
        let translator = MockParagraphAssistant(analysisResult: .success("这里用 would soften a request。"))
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "Would you mind opening the window?",
            translator: translator
        )

        await viewModel.didTapAnalyzeButton()

        XCTAssertEqual(translator.receivedAnalysisParagraphs, ["Would you mind opening the window?"])
        XCTAssertEqual(viewModel.analysis, "这里用 would soften a request。")
        XCTAssertEqual(viewModel.expandedPanel, .analysis)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testAnalyzeButtonTogglesExpansionAfterAnalysisIsLoaded() async {
        let translator = MockParagraphAssistant(analysisResult: .success("这里是俚语解释。"))
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "This is a paragraph.",
            translator: translator
        )

        await viewModel.didTapAnalyzeButton()
        await viewModel.didTapAnalyzeButton()

        XCTAssertEqual(translator.receivedAnalysisParagraphs, ["This is a paragraph."])
        XCTAssertNil(viewModel.expandedPanel)
        XCTAssertEqual(viewModel.analysis, "这里是俚语解释。")
    }

    func testSwitchingFromTranslationToAnalysisKeepsBothResultsCached() async {
        let translator = MockParagraphAssistant(
            translationResult: .success("这是译文。"),
            analysisResult: .success("这是解析。")
        )
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "This is a paragraph.",
            translator: translator
        )

        await viewModel.didTapTranslateButton()
        await viewModel.didTapAnalyzeButton()

        XCTAssertEqual(viewModel.translation, "这是译文。")
        XCTAssertEqual(viewModel.analysis, "这是解析。")
        XCTAssertEqual(viewModel.expandedPanel, .analysis)
        XCTAssertEqual(translator.receivedParagraphs, ["This is a paragraph."])
        XCTAssertEqual(translator.receivedAnalysisParagraphs, ["This is a paragraph."])
    }

    func testLoadingDifferentPanelCollapsesCurrentPanelFirst() async {
        let translator = SuspendedAnalysisParagraphAssistant()
        let viewModel = ArticleParagraphTranslationViewModel(
            paragraph: "This is a paragraph.",
            translator: translator
        )

        await viewModel.didTapTranslateButton()

        let analysisStarted = expectation(description: "analysis request starts")
        translator.onAnalysisStarted = {
            analysisStarted.fulfill()
        }

        let task = Task {
            await viewModel.didTapAnalyzeButton()
        }

        await fulfillment(of: [analysisStarted], timeout: 1)
        XCTAssertNil(viewModel.expandedPanel)
        XCTAssertEqual(viewModel.loadingPanel, .analysis)

        translator.resumeAnalysis(returning: "这是解析。")
        await task.value

        XCTAssertEqual(viewModel.expandedPanel, .analysis)
        XCTAssertEqual(viewModel.analysis, "这是解析。")
    }
}

private final class MockParagraphAssistant: ArticleParagraphTranslatorProtocol {
    var receivedParagraphs: [String] = []
    var receivedAnalysisParagraphs: [String] = []
    let translationResult: Result<String, Error>
    let analysisResult: Result<String, Error>

    init(
        translationResult: Result<String, Error> = .success("这是本段译文。"),
        analysisResult: Result<String, Error> = .success("这是本段解析。")
    ) {
        self.translationResult = translationResult
        self.analysisResult = analysisResult
    }

    func translate(paragraph: String) async throws -> String {
        receivedParagraphs.append(paragraph)
        return try translationResult.get()
    }

    func analyze(paragraph: String) async throws -> String {
        receivedAnalysisParagraphs.append(paragraph)
        return try analysisResult.get()
    }
}

private final class SuspendedAnalysisParagraphAssistant: ArticleParagraphTranslatorProtocol {
    var onAnalysisStarted: (() -> Void)?
    private var analysisContinuation: CheckedContinuation<String, Never>?

    func translate(paragraph: String) async throws -> String {
        "这是译文。"
    }

    func analyze(paragraph: String) async throws -> String {
        onAnalysisStarted?()
        return await withCheckedContinuation { continuation in
            analysisContinuation = continuation
        }
    }

    func resumeAnalysis(returning value: String) {
        analysisContinuation?.resume(returning: value)
        analysisContinuation = nil
    }
}
