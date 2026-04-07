import XCTest
@testable import VocabReader

final class MaiMemoServiceTests: XCTestCase {

    func testFetchTodayWordsParsesResponse() async throws {
        let json = """
        {"today_items": [
            {"voc_id": "id1", "voc_spelling": "apple", "order": 1, "is_new": false, "is_finished": false},
            {"voc_id": "id2", "voc_spelling": "banana", "order": 2, "is_new": true, "is_finished": false}
        ]}
        """
        let data = Data(json.utf8)
        let session = MockURLSession(data: data, statusCode: 200)
        let service = MaiMemoService(token: "test-token", session: session)

        let words = try await service.fetchTodayWords()

        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].id, "id1")
        XCTAssertEqual(words[0].spelling, "apple")
        XCTAssertEqual(words[1].id, "id2")
        XCTAssertEqual(words[1].spelling, "banana")
    }

    func testFetchTodayWordsThrowsOnHTTPError() async {
        let session = MockURLSession(data: Data(), statusCode: 401)
        let service = MaiMemoService(token: "bad-token", session: session)

        do {
            _ = try await service.fetchTodayWords()
            XCTFail("Expected error")
        } catch MaiMemoError.httpError(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testFetchDefinitionParsesFirstInterpretation() async throws {
        let json = """
        {"interpretations": [
            {"id": "iid1", "interpretation": "n. 苹果", "tags": [], "status": "PUBLISHED",
             "created_time": "2023-01-01T00:00:00Z", "updated_time": "2023-01-01T00:00:00Z"}
        ]}
        """
        let data = Data(json.utf8)
        let session = MockURLSession(data: data, statusCode: 200)
        let service = MaiMemoService(token: "test-token", session: session)

        let definition = try await service.fetchDefinition(vocId: "id1")

        XCTAssertEqual(definition, "n. 苹果")
    }

    func testFetchDefinitionReturnsNilWhenEmpty() async throws {
        let json = "{\"interpretations\": []}"
        let data = Data(json.utf8)
        let session = MockURLSession(data: data, statusCode: 200)
        let service = MaiMemoService(token: "test-token", session: session)

        let definition = try await service.fetchDefinition(vocId: "id1")

        XCTAssertNil(definition)
    }
}

// MARK: - MockURLSession

final class MockURLSession: URLSessionProtocol {
    let data: Data
    let statusCode: Int

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
