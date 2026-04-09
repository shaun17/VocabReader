import XCTest
@testable import VocabReader

@MainActor
final class SettingsConnectionDiagnosticsViewModelTests: XCTestCase {
    func testMaiMemoConnectionSuccessUpdatesStatus() async {
        let viewModel = SettingsConnectionDiagnosticsViewModel()

        await viewModel.testMaiMemoConnection(using: MockMaiMemoConnectionTester(result: .success(())))

        XCTAssertEqual(viewModel.maiMemoStatus, .success("墨墨 API 连接成功"))
    }

    func testMaiMemoConnectionFailureUpdatesStatus() async {
        let viewModel = SettingsConnectionDiagnosticsViewModel()

        await viewModel.testMaiMemoConnection(using: MockMaiMemoConnectionTester(result: .failure(MaiMemoError.httpError(401))))

        XCTAssertEqual(viewModel.maiMemoStatus, .failure("HTTP 错误 401"))
    }

    func testLLMConnectionSuccessUpdatesStatus() async {
        let viewModel = SettingsConnectionDiagnosticsViewModel()

        await viewModel.testLLMConnection(using: MockLLMConnectionTester(result: .success(())))

        XCTAssertEqual(viewModel.llmStatus, .success("LLM 连接成功"))
    }

    func testLLMConnectionFailureUpdatesStatus() async {
        let viewModel = SettingsConnectionDiagnosticsViewModel()

        await viewModel.testLLMConnection(using: MockLLMConnectionTester(result: .failure(LLMError.invalidResponse)))

        XCTAssertEqual(viewModel.llmStatus, .failure("LLM 请求地址无效，请检查 Base URL"))
    }
}

private struct MockMaiMemoConnectionTester: MaiMemoConnectionTesting {
    let result: Result<Void, Error>

    func testConnection() async throws {
        try result.get()
    }
}

private struct MockLLMConnectionTester: LLMConnectionTesting {
    let result: Result<Void, Error>

    func testConnection() async throws {
        try result.get()
    }
}
