import Foundation
import os

enum MaiMemoError: Error, LocalizedError {
    case httpError(Int)
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return Self.httpErrorDescription(code)
        case .invalidResponse: return "墨墨 API 返回了无效的响应"
        case .apiError(let msg): return msg
        }
    }

    /// 按状态码给出可操作的说明，避免首页只显示裸状态码。
    private static func httpErrorDescription(_ code: Int) -> String {
        switch code {
        case 401:
            return "墨墨 API 认证失败（HTTP 401），请在设置中检查 Token 是否正确"
        case 403:
            return "墨墨 API 拒绝访问（HTTP 403），请确认 Token 是否有效或权限是否足够"
        case 404:
            return "墨墨 API 接口不存在（HTTP 404），请稍后重试或更新应用"
        case 429:
            return "墨墨 API 请求过于频繁（HTTP 429），请稍后再试"
        case 502, 503, 504:
            return "墨墨服务暂时不可用（HTTP \(code)），可能正在维护或负载过高，请稍后重试"
        case 500..<600:
            return "墨墨服务器内部错误（HTTP \(code)），请稍后重试"
        default:
            return "墨墨 API 请求失败（HTTP \(code)）"
        }
    }
}

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

protocol MaiMemoServiceProtocol {
    func fetchTodayWords(limit: Int) async throws -> [VocabWord]
    func fetchDefinition(vocId: String) async throws -> String?
}

protocol MaiMemoConnectionTesting {
    func testConnection() async throws
}

final class MaiMemoService {
    private static let logger = Logger(subsystem: "com.vocabreader.app", category: "MaiMemoService")

    private let token: String
    private let session: URLSessionProtocol
    private let baseURL = "https://open.maimemo.com/open"

    init(token: String, session: URLSessionProtocol = URLSession.shared) {
        self.token = token
        self.session = session
    }

    func fetchTodayWords(limit: Int = 200) async throws -> [VocabWord] {
        let url = URL(string: "\(baseURL)/api/v1/study/get_today_items")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["limit": limit])

        let startedAt = Date()
        Self.logger.info("Fetching today words with limit \(limit, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MaiMemoError.invalidResponse }
        guard http.statusCode == 200 else { throw MaiMemoError.httpError(http.statusCode) }

        let decoded = try JSONDecoder().decode(TodayItemsResponse.self, from: data)
        if decoded.success == false {
            throw MaiMemoError.apiError(decoded.errors?.joined(separator: ", ") ?? "请求失败")
        }

        let words = decoded.items.map { VocabWord(id: $0.vocId, spelling: $0.vocSpelling) }
        let elapsed = Date().timeIntervalSince(startedAt)
        Self.logger.info("Fetched \(words.count, privacy: .public) words in \(elapsed, privacy: .public)s")
        return words
    }

    func fetchDefinition(vocId: String) async throws -> String? {
        var components = URLComponents(string: "\(baseURL)/api/v1/interpretations")!
        components.queryItems = [URLQueryItem(name: "voc_id", value: vocId)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MaiMemoError.invalidResponse }
        guard http.statusCode == 200 else { throw MaiMemoError.httpError(http.statusCode) }

        let decoded = try JSONDecoder().decode(InterpretationsResponse.self, from: data)
        return decoded.interpretations?.first?.interpretation
    }
}

extension MaiMemoService: MaiMemoServiceProtocol {}

extension MaiMemoService: MaiMemoConnectionTesting {
    func testConnection() async throws {
        _ = try await fetchTodayWords(limit: 1)
    }
}

// MARK: - Response types (private)

private struct TodayItemsResponse: Decodable {
    let success: Bool?
    let errors: [String]?
    let data: TodayItemsPayload?
    let todayItems: [TodayItem]?

    enum CodingKeys: String, CodingKey {
        case success
        case errors
        case data
        case todayItems = "today_items"
    }

    var items: [TodayItem] {
        data?.todayItems ?? todayItems ?? []
    }
}

private struct TodayItemsPayload: Decodable {
    let todayItems: [TodayItem]?

    enum CodingKeys: String, CodingKey {
        case todayItems = "today_items"
    }
}

private struct TodayItem: Decodable {
    let vocId: String
    let vocSpelling: String
    enum CodingKeys: String, CodingKey {
        case vocId = "voc_id"
        case vocSpelling = "voc_spelling"
    }
}

private struct InterpretationsResponse: Decodable {
    let interpretations: [InterpretationItem]?
}

private struct InterpretationItem: Decodable {
    let interpretation: String
}
