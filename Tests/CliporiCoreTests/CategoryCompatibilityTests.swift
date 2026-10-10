import XCTest
@testable import CliporiCore

final class CategoryCompatibilityTests: XCTestCase {
    func testOlderAndCustomIconCategoriesRemainReadable() throws {
        let base = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Work","color":"pink","modifiedAt":0"#
        for suffix in ["}", #", "icon":{"builtin":{"_0":"cat"}}}"#, #", "icon":{"image":{"id":"00000000-0000-0000-0000-000000000002","png":"AQID"}}}"#] {
            let category = try JSONDecoder().decode(MemoryCategory.self, from: Data((base + suffix).utf8))
            XCTAssertFalse(category.isPinboard)
            XCTAssertEqual(category.name, "Work")
            XCTAssertEqual(category.color, "pink")
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(category)) as? [String: Any]
            XCTAssertNil(encoded?["icon"])
        }
    }

    func testRepeatedCategoryEditsPersistAndSyncWithPendingChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiCategories-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("local.sqlite")
        let store = try MemoryStore(url: url)
        var category = MemoryCategory(name: "My category", color: "pink")
        try await store.saveCategory(category)
        let reopened = try MemoryStore(url: url)
        category.name = "Renamed"; category.color = "#17BFA9"; category.modifiedAt = Date()
        try await reopened.saveCategory(category)
        let rereopened = try MemoryStore(url: url)
        let saved = try await rereopened.categories().first { $0.id == category.id }
        XCTAssertEqual(saved, category)
        let remote = try MemoryStore(url: directory.appendingPathComponent("remote.sqlite"))
        _ = try await remote.mergeRemote(SyncEnvelope(category: category))
        category.isPinboard = true; category.modifiedAt = Date().addingTimeInterval(1)
        _ = try await remote.mergeRemote(SyncEnvelope(category: category))
        let synced = try await remote.categories().first { $0.id == category.id }
        XCTAssertEqual(synced, category)
    }
}
