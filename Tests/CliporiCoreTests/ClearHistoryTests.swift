import XCTest
@testable import CliporiCore

final class ClearHistoryTests: XCTestCase {
    private var directory: URL!
    private var store: MemoryStore!
    private var url: URL { directory.appendingPathComponent("history.sqlite") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiClear-\(UUID())")
        store = try MemoryStore(url: url)
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: directory) }

    func testClearIncludesAllPagesPinsAndImagesButKeepsConfiguration() async throws {
        let pinboard = MemoryCategory(name: "Saved", color: "#12BFA3", isPinboard: true)
        try await store.saveCategory(pinboard)
        let categories = try await store.categories()
        let ordered = try await store.reorderCategories(Array(categories.reversed()).map(\.id))
        var preferences = Preferences(); preferences.retentionDays = 0
        preferences.ai.model = "my-model"; preferences.ignoredApps = ["app.example"]
        try await store.savePreferences(preferences)
        for index in 0..<165 {
            var record = Memory(body: "searchable history \(index)")
            record.keepForever = index.isMultiple(of: 2)
            record.categoryID = pinboard.id; record.assignment = .manual
            try await store.save(record)
        }
        let image = try await store.saveImage(Memory(body: "Screenshot", kind: .image), png: Data([1, 2, 3]),
                                             thumbnail: Data([4, 5]), size: .init(width: 10, height: 10))
        let orphan = try await store.saveImage(Memory(body: "Deleted screenshot", kind: .image), png: Data([6, 7]),
                                              thumbnail: Data([8]), size: .init(width: 10, height: 10))
        try await store.delete(id: orphan.id)
        let deleted = try await store.deleteAllMemories()
        XCTAssertEqual(deleted, 166)
        let reopened = try MemoryStore(url: url)
        let remaining = try await reopened.count()
        let search = try await reopened.candidates(plan: SearchPlan(keywords: ["searchable"]))
        let savedCategories = try await reopened.categories()
        let savedPreferences = try await reopened.preferences()
        XCTAssertEqual(remaining, 0); XCTAssertTrue(search.isEmpty)
        XCTAssertEqual(savedCategories, ordered); XCTAssertEqual(savedPreferences, preferences)
        for attachment in [image.attachment, orphan.attachment].compactMap({ $0 }) {
            let png = try await reopened.imageData(attachment: attachment)
            let thumbnail = try await reopened.imageData(attachment: attachment, thumbnail: true)
            XCTAssertNil(png); XCTAssertNil(thumbnail)
        }
        let pending = try await reopened.syncPending(limit: 500)
        XCTAssertEqual(pending.filter { $0.kind == .memory && $0.deleted }.count, 167)
        let secondClear = try await reopened.deleteAllMemories()
        XCTAssertEqual(secondClear, 0)
        let newCopy = Memory(body: "Copied after clearing")
        try await reopened.save(newCopy)
        let newRecords = try await reopened.list()
        XCTAssertEqual(newRecords, [newCopy])
    }

    func testDeletionSyncAndLateWritesCannotRestoreClearedMemories() async throws {
        let remote = try MemoryStore(url: directory.appendingPathComponent("remote.sqlite"))
        var record = Memory(body: "Old note")
        try await store.save(record)
        try await remote.mergeRemote(SyncEnvelope(memory: record))
        try await store.deleteAllMemories()
        let envelope = try await store.syncEnvelope(key: "memory-\(record.id)")
        let deletion = try XCTUnwrap(envelope)
        XCTAssertTrue(deletion.deleted)
        try await remote.mergeRemote(deletion)
        record.modifiedAt = Date().addingTimeInterval(3600); record.body = "Late edit"
        let merged = try await store.mergeRemote(SyncEnvelope(memory: record))
        XCTAssertFalse(merged)
        let edited = try await store.saveEdit(record, isNew: false)
        XCTAssertFalse(edited)
        let classified = try await store.applyClassification(id: record.id, categoryID: nil, expectedModifiedAt: record.modifiedAt)
        XCTAssertFalse(classified)
        do { try await store.save(record); XCTFail("A delayed local write must not recreate a deleted identity") } catch {}
        let localCount = try await store.count(); let remoteCount = try await remote.count()
        XCTAssertEqual(localCount, 0); XCTAssertEqual(remoteCount, 0)
    }

    func testClearFailureRollsBackRecordsSearchPixelsAndDeletionMarkers() async throws {
        let image = try await store.saveImage(Memory(body: "Rollback image", kind: .image), png: Data([1, 2]),
                                             thumbnail: Data([3]), size: .init(width: 10, height: 10))
        let connection = try SQLiteConnection(path: url.path)
        try connection.execute("CREATE TRIGGER fail_clear BEFORE DELETE ON image_attachments BEGIN SELECT RAISE(ABORT, 'simulated failure'); END")
        do { try await store.deleteAllMemories(); XCTFail("Expected the injected failure") } catch {}
        let saved = try await store.record(id: image.id)
        let results = try await store.candidates(plan: SearchPlan(keywords: ["Rollback"]))
        let pixels = try await store.imageData(attachment: try XCTUnwrap(image.attachment))
        let envelope = try await store.syncEnvelope(key: "memory-\(image.id)")
        XCTAssertEqual(saved, image); XCTAssertEqual(results, [image]); XCTAssertEqual(pixels, Data([1, 2]))
        XCTAssertEqual(envelope?.deleted, false)
        XCTAssertTrue(try connection.rows("SELECT id FROM tombstones").isEmpty)
    }
}
