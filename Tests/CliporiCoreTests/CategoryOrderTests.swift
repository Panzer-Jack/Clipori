import XCTest
@testable import CliporiCore

final class CategoryOrderTests: XCTestCase {
    func testOrderSurvivesReopenAndCategoryEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiOrder-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("local.sqlite")
        let store = try MemoryStore(url: url)
        let original = try await store.categories()
        XCTAssertEqual(original, MemoryCategory.defaults)
        let ids = original.reversed().map(\.id)
        try await store.reorderCategories(ids)

        let reopened = try MemoryStore(url: url)
        var edited = original[2]
        edited.name = "Renamed"; edited.isPinboard = true
        try await reopened.saveCategory(edited)
        let saved = try await reopened.categories()
        XCTAssertEqual(saved.map(\.id), ids)
        XCTAssertEqual(saved.first { $0.id == edited.id }, edited)
        // Display order must not generate extra category edits for iCloud.
        let unchanged = try await reopened.syncEnvelope(key: "category-\(original[0].id.uuidString)")
        XCTAssertEqual(unchanged, try SyncEnvelope(category: original[0]))
    }

    func testStaleDragKeepsLatestDataAndAppendsNewCategories() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiOrder-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("local.sqlite"))
        let original = try await store.categories()
        try await store.deleteCategory(id: original[1].id)
        var edited = original[0]; edited.name = "Updated during drag"
        try await store.saveCategory(edited)
        let added = MemoryCategory(name: "New", color: "pink")
        try await store.saveCategory(added)
        var requested = original.reversed().map(\.id)
        requested += [original[4].id, UUID()]
        let sorted = try await store.reorderCategories(requested)
        XCTAssertEqual(sorted.map(\.id), [original[4].id, original[3].id, original[2].id, original[0].id, added.id])
        XCTAssertEqual(sorted.first { $0.id == edited.id }, edited)
    }

    func testRemoteUpdatesDoNotResetLocalOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiOrder-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("local.sqlite"))
        let original = try await store.categories()
        let ids = original.reversed().map(\.id)
        try await store.reorderCategories(ids)
        var remoteEdit = original[0]; remoteEdit.name = "Remote name"; remoteEdit.modifiedAt = Date()
        _ = try await store.mergeRemote(SyncEnvelope(category: remoteEdit))
        let added = MemoryCategory(name: "From iPhone", color: "blue")
        _ = try await store.mergeRemote(SyncEnvelope(category: added))
        let sorted = try await store.categories()
        XCTAssertEqual(sorted.map(\.id), ids + [added.id])
        XCTAssertEqual(sorted.first { $0.id == remoteEdit.id }, remoteEdit)
    }
}
