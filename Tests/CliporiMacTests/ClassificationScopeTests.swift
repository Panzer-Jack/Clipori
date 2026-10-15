import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class ClassificationScopeTests: XCTestCase {
    private func fixture(automatic: Bool) async throws -> (AppModel, URL) {
        _ = NSApplication.shared
        ClassificationScopeProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClassificationScopeProtocol.self]
        let session = URLSession(configuration: configuration)
        var ai = AIConfiguration(); ai.model = "fixture"; ai.autoClassify = automatic
        let client = AIClient(configuration: ai, apiKey: "fixture-only", session: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try AppModel(directory: directory, preview: false, classificationClientProvider: { client })
        var preferences = Preferences(); preferences.ai = ai
        try await model.store.savePreferences(preferences)
        return (model, directory)
    }
    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Classification did not finish")
    }

    func testAutomaticProcessesOnlyNewCaptureNotStartupSettingsEditOrDuplicate() async throws {
        let (model, directory) = try await fixture(automatic: true)
        defer { model.stopClassification(); try? FileManager.default.removeItem(at: directory) }
        var old = Memory(body: "old history")
        try await model.store.save(old)
        await model.start()
        try await model.updatePreferences(model.preferences)
        old.title = "edited history"; old.modifiedAt = Date()
        try await model.save(old)
        await model.accept(Memory(body: old.body))
        let fresh = Memory(body: "fresh capture")
        await model.accept(fresh)
        try await waitUntil { try await model.store.record(id: fresh.id)?.assignment == .automatic }
        XCTAssertEqual(ClassificationScopeProtocol.contents, [fresh.body])
        let unchanged = try await model.store.record(id: old.id)
        XCTAssertEqual(unchanged?.assignment, CategoryAssignment.none)
        XCTAssertNil(unchanged?.categoryID)
    }

    func testEnablingAutomaticDoesNotBackfillRecordsCapturedWhileDisabled() async throws {
        let (model, directory) = try await fixture(automatic: false)
        defer { model.stopClassification(); try? FileManager.default.removeItem(at: directory) }
        await model.start()
        let missed = Memory(body: "captured while off")
        await model.accept(missed)
        var preferences = model.preferences; preferences.ai.autoClassify = true
        try await model.updatePreferences(preferences)
        let fresh = Memory(body: "captured while on")
        await model.accept(fresh)
        try await waitUntil { try await model.store.record(id: fresh.id)?.assignment == .automatic }
        XCTAssertEqual(ClassificationScopeProtocol.contents, [fresh.body])
        let unchanged = try await model.store.record(id: missed.id)
        XCTAssertEqual(unchanged?.assignment, CategoryAssignment.none)
    }

    func testManualBatchWorksWithAutomaticOffAndIncludesEarlierNoMatchButProtectsManualChoices() async throws {
        let (model, directory) = try await fixture(automatic: false)
        defer { model.stopClassification(); try? FileManager.default.removeItem(at: directory) }
        let old = Memory(body: "old pending")
        var noMatch = Memory(body: "no match"); noMatch.assignment = .automatic
        var manual = Memory(body: "manual category"); manual.assignment = .manual; manual.categoryID = MemoryCategory.defaults[0].id
        var manualNone = Memory(body: "manual unclassified"); manualNone.assignment = .manual
        let image = Memory(body: "", kind: .image)
        var categorized = Memory(body: "already categorized"); categorized.assignment = .automatic; categorized.categoryID = MemoryCategory.defaults[1].id
        for record in [old, noMatch, manual, manualNone, image, categorized] { try await model.store.save(record) }
        await model.start()
        await model.refreshUnclassifiedCount()
        XCTAssertEqual(model.unclassifiedCount, 2)
        await model.classifyUnclassifiedRecords()
        await model.classifyUnclassifiedRecords() // Double clicks must not enqueue another batch.
        let later = Memory(body: "arrived after snapshot")
        await model.accept(later)
        try await waitUntil { !model.isClassifyingHistory }
        XCTAssertEqual(model.classificationTotal, 2)
        XCTAssertEqual(model.classificationCompleted, 2)
        XCTAssertEqual(Set(ClassificationScopeProtocol.contents), Set([old.body, noMatch.body]))
        let unchangedManual = try await model.store.record(id: manual.id)
        let unchangedLater = try await model.store.record(id: later.id)
        XCTAssertEqual(unchangedManual, manual)
        XCTAssertEqual(unchangedLater?.assignment, CategoryAssignment.none)
        // No-match results finish once rather than looping; a new explicit click may retry them.
        await model.classifyUnclassifiedRecords()
        try await waitUntil { !model.isClassifyingHistory }
        XCTAssertEqual(model.classificationTotal, 2) // no match + later
        XCTAssertEqual(ClassificationScopeProtocol.contents.filter { $0 == noMatch.body }.count, 2)
    }

    func testStoppingManualBatchLeavesUnprocessedHistoryForNextExplicitRun() async throws {
        let (model, directory) = try await fixture(automatic: false)
        defer { model.stopClassification(); try? FileManager.default.removeItem(at: directory) }
        for index in 0..<5 { try await model.store.save(Memory(body: "pending \(index)")) }
        await model.start()
        await model.classifyUnclassifiedRecords()
        model.stopClassification()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.isClassifyingHistory)
        XCTAssertLessThan(ClassificationScopeProtocol.contents.count, 5)
        let pending = try await model.store.unclassifiedCount()
        XCTAssertGreaterThan(pending, 0)
    }
}

private final class ClassificationScopeProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var captured: [String] = []
    static var contents: [String] { lock.withLock { captured } }
    static func reset() { lock.withLock { captured = [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data: Data
            if let body = request.httpBody { data = body }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    result.append(buffer, count: count)
                }
                data = result
            } else { throw URLError(.badServerResponse) }
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
            let input = try XCTUnwrap(messages.last?["content"]?.data(using: .utf8))
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
            let body = try XCTUnwrap(record["content"] as? String)
            Self.lock.withLock { Self.captured.append(body) }
            let category: Any = body == "no match" ? NSNull() : MemoryCategory.defaults[0].id.uuidString
            let answer = String(decoding: try JSONSerialization.data(withJSONObject: ["categoryID": category]), as: UTF8.self)
            let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": answer]]]])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
