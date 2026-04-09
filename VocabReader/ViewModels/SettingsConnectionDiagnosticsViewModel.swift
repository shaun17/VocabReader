import Foundation

enum ConnectionTestStatus: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

@MainActor
final class SettingsConnectionDiagnosticsViewModel: ObservableObject {
    @Published var maiMemoStatus: ConnectionTestStatus = .idle
    @Published var llmStatus: ConnectionTestStatus = .idle

    func testMaiMemoConnection(using tester: MaiMemoConnectionTesting) async {
        maiMemoStatus = .testing

        do {
            try await tester.testConnection()
            maiMemoStatus = .success("墨墨 API 连接成功")
        } catch {
            maiMemoStatus = .failure(error.localizedDescription)
        }
    }

    func testLLMConnection(using tester: LLMConnectionTesting) async {
        llmStatus = .testing

        do {
            try await tester.testConnection()
            llmStatus = .success("LLM 连接成功")
        } catch {
            llmStatus = .failure(error.localizedDescription)
        }
    }
}
