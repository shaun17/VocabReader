import Foundation

enum MaiMemoError: Error {
    case httpError(Int)
    case invalidResponse
}

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

protocol MaiMemoServiceProtocol {
    func fetchTodayWords(limit: Int) async throws -> [VocabWord]
    func fetchDefinition(vocId: String) async throws -> String?
}

final class MaiMemoService {
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

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MaiMemoError.invalidResponse }
        guard http.statusCode == 200 else { throw MaiMemoError.httpError(http.statusCode) }

        let decoded = try JSONDecoder().decode(TodayItemsResponse.self, from: data)
        return decoded.todayItems.map { VocabWord(id: $0.vocId, spelling: $0.vocSpelling) }
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
        return decoded.interpretations.first?.interpretation
    }
}

extension MaiMemoService: MaiMemoServiceProtocol {}

// MARK: - Response types (private)

private struct TodayItemsResponse: Decodable {
    let todayItems: [TodayItem]
    enum CodingKeys: String, CodingKey { case todayItems = "today_items" }
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
    let interpretations: [InterpretationItem]
}

private struct InterpretationItem: Decodable {
    let interpretation: String
}
