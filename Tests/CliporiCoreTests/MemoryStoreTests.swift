import XCTest
@testable import CliporiCore

final class MemoryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: MemoryStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiTests-\(UUID().uuidString)")
        store = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: directory) }

    func testDefaultMonthWithForeverAndExplicitExceptions() async throws {
        let now = Date()
        var automatic = Memory(body: "old copied text", source: "Safari", now: now.addingTimeInterval(-100 * 86400))
        var edited = Memory(body: "hand edited note", now: now.addingTimeInterval(-90 * 86400)); edited.modifiedAt = now
        var protected = Memory(body: "user exception", now: now.addingTimeInterval(-100 * 86400)); protected.keepForever = true
        automatic.assignment = .automatic
        for record in [automatic, edited, protected, Memory(body: "recent", now: now)] { try await store.save(record) }
        let preferences = try await store.preferences()
        XCTAssertEqual(preferences.retentionDays, 30)
        let noCleanup = try await store.clean(retentionDays: 0, now: now)
        XCTAssertEqual(noCleanup, 0)
        let cleaned = try await store.clean(retentionDays: 30, now: now)
        XCTAssertEqual(cleaned, 2)
        let remaining = try await store.list()
        XCTAssertEqual(Set(remaining.map(\.body)), ["user exception", "recent"])
        let removedCandidates = try await store.candidates(plan: SearchPlan(keywords: ["copied"]))
        XCTAssertTrue(removedCandidates.isEmpty)
    }

    func testPinboardProtectsOldItemsButOrdinaryCategoriesDoNot() async throws {
        let now = Date(), old = Date().addingTimeInterval(-86400 * 400)
        let pinboard = MemoryCategory(name: "Keep", color: "pink", isPinboard: true)
        try await store.saveCategory(pinboard)
        var kept = Memory(body: "saved to pinboard", now: old); kept.categoryID = pinboard.id; kept.assignment = .manual
        var ordinary = Memory(body: "normal category", now: old); ordinary.categoryID = MemoryCategory.defaults[0].id
        try await store.save(kept); try await store.save(ordinary)
        let removed = try await store.clean(retentionDays: 30, now: now)
        XCTAssertEqual(removed, 1)
        let remaining = try await store.list()
        XCTAssertEqual(remaining.map(\.id), [kept.id])
        try await store.deleteCategory(id: pinboard.id)
        let moved = try await store.record(id: kept.id)
        XCTAssertNotNil(moved); XCTAssertNil(moved?.categoryID)
        let afterRemoval = try await store.clean(retentionDays: 30, now: now)
        XCTAssertEqual(afterRemoval, 1)
    }

    func testLateClassificationCannotAddItemsToPinboard() async throws {
        let category = MemoryCategory(name: "Hand-picked", color: "pink", isPinboard: true)
        try await store.saveCategory(category)
        let record = Memory(body: "do not automatically preserve")
        try await store.save(record)
        let applied = try await store.applyClassification(id: record.id, categoryID: category.id, expectedModifiedAt: record.modifiedAt)
        XCTAssertFalse(applied)
    }

    func testExistingInstallWithoutPreferencesKeepsForeverOnUpgrade() async throws {
        let database = try SQLiteConnection(path: directory.appendingPathComponent("test.sqlite").path)
        try database.execute("DELETE FROM metadata WHERE key='preferences'")
        let reopen = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let legacy = try await reopen.preferences()
        XCTAssertEqual(legacy.retentionDays, 0)
        var custom = legacy; custom.retentionDays = 90
        try await reopen.savePreferences(custom)
        let thirdOpen = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let persisted = try await thirdOpen.preferences()
        XCTAssertEqual(persisted.retentionDays, 90)
    }

    func testEditsImmediatelyReplaceSearchIndexAndPersist() async throws {
        var record = Memory(body: "上周去过的餐厅是青山食堂，地址花园路18号")
        try await store.save(record)
        let found = try await store.candidates(plan: SearchPlan(keywords: ["餐厅", "青山"]))
        XCTAssertEqual(found.first?.id, record.id)
        record.body = "新的备忘：樱花咖啡店，营业到晚上九点"; record.modifiedAt = Date()
        try await store.save(record)
        let old = try await store.candidates(plan: SearchPlan(keywords: ["青山"]))
        let edited = try await store.list(query: "咖啡")
        XCTAssertTrue(old.isEmpty); XCTAssertEqual(edited.first?.body, record.body)
        let reopened = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let persisted = try await reopened.record(id: record.id)
        XCTAssertEqual(persisted, record)
    }

    func testLiteralSearchDoesNotInterpretSQLWildcards() async throws {
        try await store.save(Memory(body: "优惠 50%_off"))
        try await store.save(Memory(body: "另一条普通记录"))
        let result = try await store.list(query: "%_")
        XCTAssertEqual(result.count, 1)
    }

    func testBatchClassificationUsesLatestContentAndSkipsDeletedRecords() async throws {
        var first = Memory(body: "original"), second = Memory(body: "second")
        let removed = Memory(body: "deleted while dragging")
        for record in [first, second, removed] { try await store.save(record) }
        let before = first.modifiedAt
        first.body = "newer text edited while dragging"; first.keepForever = true
        try await store.save(first)
        try await store.delete(id: removed.id)
        second.categoryID = MemoryCategory.defaults[0].id
        let changed = try await store.assign(ids: [first.id, second.id, removed.id, first.id], to: second.categoryID)
        XCTAssertEqual(changed.map(\.id), [first.id, second.id])
        XCTAssertEqual(changed[0].body, first.body)
        XCTAssertTrue(changed[0].keepForever)
        XCTAssertTrue(changed.allSatisfy { $0.categoryID == second.categoryID && $0.assignment == .manual })
        let lateAI = try await store.applyClassification(id: first.id, categoryID: nil, expectedModifiedAt: before)
        XCTAssertFalse(lateAI)
        let found = try await store.candidates(plan: SearchPlan(keywords: ["newer"]))
        XCTAssertEqual(found.first?.id, first.id)
        let reopen = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let persisted = try await reopen.record(id: first.id)
        XCTAssertEqual(persisted, changed[0])
        let count = try await reopen.count()
        XCTAssertEqual(count, 2)
        let pending = try await store.syncPending()
        XCTAssertTrue(pending.contains { $0.id == first.id && !$0.deleted })
    }

    func testBatchClassificationRollsBackWhenOneUpdateFailsAndRejectsDeletedCategory() async throws {
        let records = [Memory(body: "first"), Memory(body: "second")]
        for record in records { try await store.save(record) }
        let database = try SQLiteConnection(path: directory.appendingPathComponent("test.sqlite").path)
        try database.execute("CREATE TRIGGER fail_move BEFORE UPDATE ON memories WHEN NEW.id='\(records[1].id.uuidString)' BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END")
        do {
            _ = try await store.assign(ids: records.map(\.id), to: MemoryCategory.defaults[0].id)
            XCTFail("The failing update must abort the whole batch")
        } catch {}
        for record in records {
            let saved = try await store.record(id: record.id)
            XCTAssertEqual(saved, record)
        }
        try database.execute("DROP TRIGGER fail_move")
        let deletedCategory = MemoryCategory.defaults[0].id
        try await store.deleteCategory(id: deletedCategory)
        do {
            _ = try await store.assign(ids: records.map(\.id), to: deletedCategory)
            XCTFail("A stale drop target must not create orphan category references")
        } catch {}
        let saved = try await store.record(id: records[0].id)
        XCTAssertNil(saved?.categoryID)
    }

    func testOpenEditorCannotResurrectExpiredRecord() async throws {
        var record = Memory(body: "old note", now: Date().addingTimeInterval(-86400 * 60))
        try await store.save(record)
        try await store.clean(retentionDays: 30)
        record.body = "late autosave"; record.modifiedAt = Date()
        let saved = try await store.saveEdit(record, isNew: false)
        let count = try await store.count()
        XCTAssertFalse(saved); XCTAssertEqual(count, 0)
    }

    func testLateAIResponseCannotOverwriteManualChangeOrRestoreDeletion() async throws {
        var record = Memory(body: "code snippet")
        try await store.save(record)
        let oldRevision = record.modifiedAt
        record.assignment = .manual; record.categoryID = MemoryCategory.defaults[0].id; record.modifiedAt = Date().addingTimeInterval(1)
        try await store.save(record)
        let applied = try await store.applyClassification(id: record.id, categoryID: MemoryCategory.defaults[3].id, expectedModifiedAt: oldRevision)
        XCTAssertFalse(applied)
        let latest = try await store.record(id: record.id)
        XCTAssertEqual(latest?.categoryID, MemoryCategory.defaults[0].id)
        try await store.delete(id: record.id)
        let afterDelete = try await store.applyClassification(id: record.id, categoryID: nil, expectedModifiedAt: record.modifiedAt)
        let count = try await store.count()
        XCTAssertFalse(afterDelete); XCTAssertEqual(count, 0)
    }

    func testDeleteCategoryKeepsMemoriesAndDoesNotReseedDeletedDefaults() async throws {
        let category = MemoryCategory.defaults[0]
        var record = Memory(body: "work note"); record.categoryID = category.id
        try await store.save(record); try await store.deleteCategory(id: category.id)
        let saved = try await store.record(id: record.id)
        XCTAssertNotNil(saved); XCTAssertNil(saved?.categoryID)
        let reopen = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let categories = try await reopen.categories()
        XCTAssertFalse(categories.contains { $0.id == category.id })
    }

    func testRetrievalIncludesOlderRecordsBeyondFirstPage() async throws {
        let old = Memory(body: "给妈妈买的礼物：蓝色围巾", now: Date().addingTimeInterval(-86400 * 50))
        try await store.save(old)
        for index in 0..<160 { try await store.save(Memory(body: "普通备忘 \(index)")) }
        let first = try await store.list()
        XCTAssertEqual(first.count, 80); XCTAssertFalse(first.contains { $0.id == old.id })
        let found = try await store.candidates(plan: SearchPlan(keywords: ["围巾", "礼物"]))
        XCTAssertEqual(found.first?.id, old.id)
    }
}
