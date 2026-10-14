import XCTest
@testable import CliporiCore

final class AIRequestDeadlineTests: XCTestCase {
    func testExistingRequestsKeepTheirTimeoutAndDailyDraftCanWaitLonger() throws {
        let client = client()
        XCTAssertEqual(try client.makeRequest(system: "", user: "").timeoutInterval, 45)
        XCTAssertEqual(try client.makeRequest(system: "", user: "", timeout: AIClient.dailyNoteTimeout).timeoutInterval, 180)
    }

    func testDeadlineCancelsUnderlyingNetworkRequest() async throws {
        let stopped = expectation(description: "transport cancelled at deadline")
        DelayedAIProtocol.delay = 2
        DelayedAIProtocol.onStop = { stopped.fulfill() }
        defer { DelayedAIProtocol.onStop = nil }
        do {
            _ = try await client().complete(system: "", user: "", timeout: 0.05)
            XCTFail("A slow response must not outlive the explicit deadline")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testResponseBeforeDeadlineSucceeds() async throws {
        DelayedAIProtocol.delay = 0.1
        let result = try await client().complete(system: "", user: "", timeout: 2)
        XCTAssertEqual(result, "OK")
    }

    func testUserCancellationDoesNotWaitForDeadline() async throws {
        let started = expectation(description: "transport started")
        let stopped = expectation(description: "transport cancelled by user")
        DelayedAIProtocol.delay = 30
        DelayedAIProtocol.onStart = { started.fulfill() }
        DelayedAIProtocol.onStop = { stopped.fulfill() }
        defer { DelayedAIProtocol.onStart = nil; DelayedAIProtocol.onStop = nil }
        let client = client()
        let task = Task { try await client.complete(system: "", user: "", timeout: 180) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation should not produce an answer") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [stopped], timeout: 2)
    }

    private func client() -> AIClient {
        var config = AIConfiguration(); config.model = "test"
        let transport = URLSessionConfiguration.ephemeral; transport.protocolClasses = [DelayedAIProtocol.self]
        return AIClient(configuration: config, apiKey: "test-only", session: URLSession(configuration: transport))
    }
}

private final class DelayedAIProtocol: URLProtocol {
    static var delay: TimeInterval = 0
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: item)
        Self.onStart?()
    }
    override func stopLoading() { work?.cancel(); Self.onStop?() }
}
