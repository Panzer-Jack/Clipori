import XCTest
@testable import CliporiCore

final class AIClientTests: XCTestCase {
    func testLongNoteContextIncludesLaterAdditionsWithoutExceedingBudget() {
        let addition = "追加：餐厅改为樱花食堂，地址青山路42号。"
        let body = "餐厅待定。" + String(repeating: "日常备忘🌸 ", count: 2000) + addition
        let excerpt = AIClient.searchExcerpt(body, keywords: ["餐厅", "樱花"], limit: 2200)
        XCTAssertTrue(excerpt.contains(addition), "AI must see matches after the beginning of a long note")
        XCTAssertLessThanOrEqual(excerpt.count, 2200)
        XCTAssertEqual(AIClient.searchExcerpt("short note", keywords: ["note"], limit: 2200), "short note")
        XCTAssertTrue(AIClient.searchExcerpt(body, keywords: ["餐厅"], limit: 0).isEmpty)
    }

    func testOpenAIRequestAndCustomBasePaths() throws {
        var config = AIConfiguration(); config.model = "custom-model"; config.baseURL = "https://example.com/proxy/v1/"
        let request = try AIClient(configuration: config, apiKey: "test-only").makeRequest(system: "system", user: "question")
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/proxy/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "custom-model")
        XCTAssertEqual((body["messages"] as? [[String: String]])?.first?["role"], "system")
        config.baseURL = "https://example.com/v1/chat/completions"
        XCTAssertEqual(try AIClient(configuration: config, apiKey: "test-only").makeRequest(system: "", user: "").url?.path, "/v1/chat/completions")
    }
    func testClaudeMessagesFormat() throws {
        var config = AIConfiguration(); config.format = .claude; config.baseURL = "https://api.anthropic.com"; config.model = "custom-claude"
        let request = try AIClient(configuration: config, apiKey: "test-only").makeRequest(system: "rules", user: "hello")
        XCTAssertEqual(request.url?.path, "/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-only")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "rules")
        XCTAssertEqual(body["max_tokens"] as? Int, 2048)
    }
    func testRejectsUnsafeEndpointAndMissingConfiguration() throws {
        var config = AIConfiguration(); config.model = "test"; config.baseURL = "http://remote.example.com"
        XCTAssertThrowsError(try AIClient(configuration: config, apiKey: "key").makeRequest(system: "", user: ""))
        config.baseURL = "http://127.0.0.1:8080/v1"
        XCTAssertNoThrow(try AIClient(configuration: config, apiKey: "key").makeRequest(system: "", user: ""))
        XCTAssertThrowsError(try AIClient(configuration: config, apiKey: "").makeRequest(system: "", user: ""))
    }
    func testNetworkResponsesAndServiceErrors() async throws {
        let session = mockSession()
        var config = AIConfiguration(); config.model = "test"
        MockProtocol.responses = [(200, "{\"choices\":[{\"message\":{\"content\":\"OK\"}}]}")]
        let client = AIClient(configuration: config, apiKey: "test", session: session)
        let response = try await client.complete(system: "", user: "")
        XCTAssertEqual(response, "OK")
        MockProtocol.responses = [(401, "{}")]
        do { _ = try await client.complete(system: "", user: ""); XCTFail("Must reject auth failure") }
        catch { XCTAssertEqual(error as? AIError, .service(401)) }
        config.format = .claude
        MockProtocol.responses = [(200, "{\"content\":[{\"type\":\"text\",\"text\":\"Claude OK\"}]}")]
        let claude = try await AIClient(configuration: config, apiKey: "test", session: session).complete(system: "", user: "")
        XCTAssertEqual(claude, "Claude OK")
    }
    func testSearchFiltersFabricatedCitations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let record = Memory(body: "餐厅名字是青山食堂")
        try await store.save(record)
        var config = AIConfiguration(); config.model = "test"
        let plan = "{\"keywords\":[\"餐厅\"],\"startDate\":null,\"endDate\":null}"
        let answer = "{\"matches\":[{\"id\":\"\(UUID().uuidString)\",\"quote\":\"捏造的内容\"}]}"
        MockProtocol.responses = [(200, try envelope(plan)), (200, try envelope(answer))]
        let result = try await AIClient(configuration: config, apiKey: "test", session: mockSession()).search("餐厅叫什么", store: store)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertFalse(result.answer.contains("捏造"))
    }
    func testSearchReturnsVerifiedEvidenceAndRejectsInventedQuote() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let record = Memory(body: "餐厅名字是青山食堂，地址花园路18号")
        try await store.save(record)
        var config = AIConfiguration(); config.model = "test"
        let plan = "{\"keywords\":[\"餐厅\"]}"
        let answer = "{\"matches\":[{\"id\":\"\(record.id.uuidString)\",\"quote\":\"地址花园路18号\"}]}"
        MockProtocol.responses = [(200, try envelope(plan)), (200, try envelope(answer))]
        let result = try await AIClient(configuration: config, apiKey: "test", session: mockSession()).search("地址在哪", store: store)
        XCTAssertEqual(result.records.first?.id, record.id)
        XCTAssertEqual(result.answer, "[1] 地址花园路18号")
        let invented = "{\"matches\":[{\"id\":\"\(record.id.uuidString)\",\"quote\":\"地址中山路888号\"}]}"
        MockProtocol.responses = [(200, try envelope(plan)), (200, try envelope(invented))]
        let rejected = try await AIClient(configuration: config, apiKey: "test", session: mockSession()).search("地址在哪", store: store)
        XCTAssertTrue(rejected.records.isEmpty)
    }
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        return URLSession(configuration: config)
    }
    private func envelope(_ content: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]]), as: UTF8.self)
    }
}

private final class MockProtocol: URLProtocol {
    static var responses: [(Int, String)] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.responses.isEmpty else { client?.urlProtocol(self, didFailWithError: AIError.emptyResponse); return }
        let next = Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
