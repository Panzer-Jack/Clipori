import XCTest
@testable import CliporiCore

final class SyncStoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func store(_ name: String) throws -> MemoryStore { try MemoryStore(url: directory.appendingPathComponent(name + ".sqlite")) }

    func testOutboxSurvivesRestartAndOldAcknowledgementKeepsNewEdit() async throws {
        let first = try store("one")
        var memory = Memory(body: "初稿")
        try await first.save(memory)
        let uploaded = try SyncEnvelope(memory: memory)
        memory.body = "离线追加"; memory.modifiedAt = Date().addingTimeInterval(1)
        try await first.save(memory)
        try await first.syncAcknowledge(uploaded, systemFields: Data([1]))
        let reopened = try store("one")
        let pending = try await reopened.syncPending()
        XCTAssertTrue(pending.contains { $0 == (try? SyncEnvelope(memory: memory)) })
        try await reopened.syncAcknowledge(SyncEnvelope(memory: memory), systemFields: Data([2]))
        let after = try await reopened.syncPending()
        XCTAssertFalse(after.contains { $0.id == memory.id })
    }
    func testDeletionWinsOverOfflineEditAndRemovesSearchEvidence() async throws {
        let first = try store("one"); let second = try store("two")
        var memory = Memory(body: "云端咖啡馆")
        try await first.save(memory)
        try await second.mergeRemote(SyncEnvelope(memory: memory))
        let deletion = SyncEnvelope(deleting: memory.id, kind: .memory, at: Date())
        try await first.mergeRemote(deletion)
        memory.body += " 离线改动"; memory.modifiedAt = Date().addingTimeInterval(100)
        try await second.save(memory)
        try await first.mergeRemote(SyncEnvelope(memory: memory))
        try await second.mergeRemote(deletion)
        let missing = try await second.record(id: memory.id)
        let results = try await second.candidates(plan: .init(keywords: ["咖啡馆"]))
        XCTAssertNil(missing); XCTAssertTrue(results.isEmpty)
        let stillDeleted = try await first.syncEnvelope(key: deletion.key)
        XCTAssertEqual(stillDeleted, deletion)
    }
    func testCategoryDeletionIsOrderIndependentAndManualAssignmentSurvives() async throws {
        let first = try store("one")
        let category = MemoryCategory(name: "旅行", color: "blue")
        try await first.saveCategory(category)
        var memory = Memory(body: "机票"); memory.categoryID = category.id; memory.assignment = .manual
        try await first.save(memory)
        var automatic = memory; automatic.categoryID = MemoryCategory.defaults[0].id
        automatic.assignment = .automatic; automatic.modifiedAt = Date().addingTimeInterval(1)
        try await first.mergeRemote(SyncEnvelope(memory: automatic))
        let kept = try await first.record(id: memory.id)
        XCTAssertEqual(kept?.categoryID, category.id)
        let deletion = SyncEnvelope(deleting: category.id, kind: .category, at: Date())
        try await first.mergeRemote(deletion)
        memory.modifiedAt = Date().addingTimeInterval(2)
        try await first.mergeRemote(SyncEnvelope(memory: memory))
        let cleared = try await first.record(id: memory.id)
        XCTAssertNil(cleared?.categoryID); XCTAssertEqual(cleared?.assignment, .manual)
    }
    func testEqualClockConflictsConvergeAndPreferencesNeverEnterOutbox() async throws {
        let first = try store("one"); let second = try store("two")
        let a = Memory(body: "A")
        var b = a; b.body = "B"
        try await first.save(a); try await second.save(b)
        try await first.mergeRemote(SyncEnvelope(memory: b)); try await second.mergeRemote(SyncEnvelope(memory: a))
        let left = try await first.record(id: a.id); let right = try await second.record(id: a.id)
        XCTAssertEqual(left, right)
        let before = try await first.syncPending()
        var preferences = Preferences(); preferences.ai.baseURL = "https://private.example/v1"
        try await first.savePreferences(preferences)
        let after = try await first.syncPending()
        XCTAssertEqual(before, after)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(after), as: UTF8.self).contains("private.example"))
    }
}
