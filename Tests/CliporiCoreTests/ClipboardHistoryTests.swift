import XCTest
@testable import CliporiCore

final class ClipboardHistoryTests: XCTestCase {
    private var directory: URL!
    private var store: MemoryStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiClipboard-\(UUID())")
        store = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: directory) }

    func testDuplicateCaptureReusesRecordAndPreservesUserMetadata() async throws {
        var original = Memory(title: "User title", body: "same text", source: "Safari", now: Date(timeIntervalSince1970: 100))
        original.categoryID = MemoryCategory.defaults[0].id; original.assignment = .manual; original.keepForever = true
        try await store.save(original)
        let newer = Memory(body: "different", now: Date(timeIntervalSince1970: 200))
        try await store.captureText(newer)
        let reused = try await store.captureText(Memory(body: original.body, source: "Xcode", now: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(reused, original)
        let records = try await store.list()
        XCTAssertEqual(records.map(\.id), [newer.id, original.id])
        let classified = try await store.list(categoryID: original.categoryID)
        XCTAssertEqual(classified, [original])
        let found = try await store.candidates(plan: SearchPlan(keywords: ["same"]))
        XCTAssertEqual(found.map(\.id), [original.id])
    }

    func testExactMatchingPreservesWhitespaceCaseUnicodeAndImageNotes() async throws {
        let bodies = ["text", " text", "text ", "text\n", "Text", "a\nb", "a\r\nb", "é", "e\u{301}", "text\0suffix"]
        for body in bodies {
            try await store.captureText(Memory(body: body))
            try await store.captureText(Memory(body: body))
        }
        let records = try await store.list()
        XCTAssertEqual(records.count, bodies.count)
        XCTAssertEqual(Set(records.map { Data($0.body.utf8) }), Set(bodies.map { Data($0.utf8) }))
        let image = Memory(body: "image note", kind: .image)
        try await store.save(image)
        let text = try await store.captureText(Memory(body: image.body))
        XCTAssertNotEqual(text.id, image.id)
        XCTAssertEqual(text.kind, .text)
    }

    func testConcurrentCapturesAndDuplicateBeyondFirstPage() async throws {
        let original = Memory(body: "old duplicate", now: Date(timeIntervalSince1970: 100))
        try await store.save(original)
        for index in 0..<100 { try await store.save(Memory(body: "new \(index)")) }
        let store = try XCTUnwrap(store)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { try await store.captureText(Memory(body: original.body)) } }
            try await group.waitForAll()
        }
        let count = try await store.count()
        let records = try await store.list()
        XCTAssertEqual(count, 101)
        XCTAssertFalse(records.contains { $0.id == original.id })
        let next = try await store.list(offset: 80)
        XCTAssertEqual(next.last?.id, original.id)
        XCTAssertEqual(Set((records + next).map(\.id)).count, 101)
    }

    func testPromotionSurvivesEditsAndReopenWithoutExtendingRetention() async throws {
        let now = Date()
        var old = Memory(body: "old", now: now.addingTimeInterval(-60 * 86400))
        let recent = Memory(body: "recent", now: now.addingTimeInterval(-1))
        for record in [old, recent] { try await store.save(record) }
        try await store.markUsed(id: old.id, at: now)
        old.title = "edited after paste"; old.modifiedAt = now
        let saved = try await store.saveEdit(old, isNew: false)
        XCTAssertTrue(saved)
        let reopened = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let records = try await reopened.list()
        XCTAssertEqual(records, [old, recent])
        let removed = try await reopened.clean(retentionDays: 30, now: now)
        XCTAssertEqual(removed, 1)
        let promotedDeleted = try await reopened.markUsed(id: old.id)
        XCTAssertFalse(promotedDeleted)
        let remaining = try await reopened.list()
        XCTAssertEqual(remaining, [recent])
    }

    func testOldSchemaMigratesWithoutChangingRecords() async throws {
        let url = directory.appendingPathComponent("legacy.sqlite")
        let db = try SQLiteConnection(path: url.path)
        try db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY, body TEXT NOT NULL, title TEXT NOT NULL, created REAL NOT NULL, modified REAL NOT NULL, category TEXT, protected INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL)")
        let old = Memory(body: "legacy", now: Date(timeIntervalSince1970: 100))
        try db.execute("INSERT INTO memories VALUES (?, ?, '', 100, 100, NULL, 0, ?)", [
            .text(old.id.uuidString), .text(old.body), .text(String(decoding: try JSONEncoder().encode(old), as: UTF8.self))
        ])
        let upgraded = try MemoryStore(url: url)
        let records = try await upgraded.list()
        XCTAssertEqual(records, [old])
        let captured = try await upgraded.captureText(Memory(body: old.body))
        XCTAssertEqual(captured, old)
        let reopened = try MemoryStore(url: url)
        let count = try await reopened.count()
        XCTAssertEqual(count, 1)
    }

    func testNineColumnPreviewMigratesBackAndAnAlreadyOpenLegacyConnectionCanWrite() async throws {
        let url = directory.appendingPathComponent("test.sqlite")
        let legacy = try SQLiteConnection(path: url.path)
        let old = Memory(body: "promoted", now: Date(timeIntervalSince1970: 100))
        let newer = Memory(body: "newer", now: Date(timeIntervalSince1970: 200))
        for record in [old, newer] { try await store.save(record) }
        // Reproduce the schema shipped in the first preview, including its dependent indexes.
        try legacy.execute("ALTER TABLE memories ADD COLUMN last_used REAL")
        try legacy.execute("CREATE INDEX memory_recent ON memories(COALESCE(last_used, created) DESC, id DESC)")
        try legacy.execute("CREATE INDEX memory_category_recent ON memories(category, COALESCE(last_used, created) DESC, id DESC)")
        try legacy.execute("UPDATE memories SET last_used=300 WHERE id=?", [.text(old.id.uuidString)])

        let repaired = try MemoryStore(url: url)
        XCTAssertEqual(try legacy.rows("PRAGMA table_info(memories)").count, 8)
        let records = try await repaired.list()
        XCTAssertEqual(records, [old, newer])

        // The installed version does not name its columns; this must remain valid after migration.
        let captured = Memory(body: "captured by installed app", now: Date(timeIntervalSince1970: 400))
        try legacy.execute("INSERT OR REPLACE INTO memories VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
            .text(captured.id.uuidString), .text(captured.body), .text(captured.title),
            .number(400), .number(400), .null, .number(0),
            .text(String(decoding: try JSONEncoder().encode(captured), as: UTF8.self))
        ])
        let reopened = try MemoryStore(url: url)
        let afterLegacyWrite = try await reopened.list()
        XCTAssertEqual(afterLegacyWrite, [captured, old, newer])
        XCTAssertEqual(try legacy.rows("PRAGMA foreign_key_check"), [])
    }

    func testRecencyStaysOutOfSyncOutboxAndIsRemovedWithItsRecord() async throws {
        let record = Memory(body: "local recency")
        try await store.save(record)
        try await store.syncAcknowledge(SyncEnvelope(memory: record), systemFields: Data())
        try await store.markUsed(id: record.id)
        let pending = try await store.syncPending()
        XCTAssertFalse(pending.contains { $0.id == record.id })
        let db = try SQLiteConnection(path: directory.appendingPathComponent("test.sqlite").path)
        XCTAssertEqual(try db.rows("SELECT count(*) FROM memory_recency").first?.first, "1")
        try await store.delete(id: record.id)
        XCTAssertEqual(try db.rows("SELECT count(*) FROM memory_recency").first?.first, "0")
    }

    func testCharacterCountUsesFullTextAndUserPerceivedCharacters() {
        XCTAssertEqual(Memory(body: "中文 Ab 12，!\n\t\r\n\u{3000}👨‍👩‍👧‍👦 e\u{301}").characterCount, 10)
        XCTAssertEqual(Memory(body: " \n\t").characterCount, 0)
        XCTAssertEqual(Memory(body: String(repeating: "字", count: 2000)).characterCount, 2000)
    }
}
