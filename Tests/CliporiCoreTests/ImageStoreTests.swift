import XCTest
@testable import CliporiCore

final class ImageStoreTests: XCTestCase {
    private var directory: URL!
    private var store: MemoryStore!
    private let pixels = Data([0, 255, 0, 128, 1, 2, 3])
    private let thumbnail = Data([0, 1, 255, 128])
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiImageStore-\(UUID())")
        store = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: directory) }

    func testImagePersistsAcrossReopenAndNotesAreSearchableWithoutChangingPixels() async throws {
        var record = try await store.saveImage(Memory(body: "", kind: .image), png: pixels, thumbnail: thumbnail, size: .init(width: 400, height: 300))
        let attachment = try XCTUnwrap(record.attachment)
        record.title = "截图"; record.body = "会议地址：樱花咖啡店"; record.modifiedAt = Date()
        let saved = try await store.saveEdit(record, isNew: false)
        XCTAssertTrue(saved)
        let reopened = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        let restored = try await reopened.record(id: record.id)
        let originalData = try await reopened.imageData(attachment: attachment)
        let thumbnailData = try await reopened.imageData(attachment: attachment, thumbnail: true)
        XCTAssertEqual(restored, record)
        XCTAssertEqual(originalData, pixels); XCTAssertEqual(thumbnailData, thumbnail)
        let results = try await reopened.candidates(plan: SearchPlan(keywords: ["樱花", "咖啡"] ))
        XCTAssertEqual(results.map(\.id), [record.id])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Memory(body: "old text"))) as? [String: Any])
        legacy.removeValue(forKey: "imageSize")
        let decoded = try JSONDecoder().decode(Memory.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.imageSize)
    }

    func testUndoKeepsPixelsAndPruningReclaimsOnlyUnreferencedImages() async throws {
        let record = try await store.saveImage(Memory(body: "", kind: .image), png: pixels, thumbnail: thumbnail, size: .init(width: 40, height: 30))
        let attachment = try XCTUnwrap(record.attachment)
        try await store.delete(id: record.id)
        try await store.pruneImages(keeping: [attachment])
        let retained = try await store.imageData(attachment: attachment)
        XCTAssertEqual(retained, pixels)
        var restored = record; restored.id = UUID(); restored.modifiedAt = Date()
        try await store.save(restored)
        try await store.pruneImages()
        let live = try await store.imageData(attachment: attachment)
        XCTAssertEqual(live, pixels)
        try await store.delete(id: restored.id)
        try await store.pruneImages()
        let removed = try await store.imageData(attachment: attachment)
        let removedThumbnail = try await store.imageData(attachment: attachment, thumbnail: true)
        XCTAssertNil(removed); XCTAssertNil(removedThumbnail)
    }

    func testRetentionCleansImageAttachmentsAndRespectsPinboards() async throws {
        let pinboard = MemoryCategory(name: "Keep screenshots", color: "pink", isPinboard: true)
        try await store.saveCategory(pinboard)
        let old = Memory(body: "", kind: .image, now: Date().addingTimeInterval(-86400 * 60))
        let expired = try await store.saveImage(old, png: pixels, thumbnail: thumbnail, size: .init(width: 40, height: 30))
        var pinned = old; pinned.id = UUID(); pinned.categoryID = pinboard.id
        let kept = try await store.saveImage(pinned, png: pixels, thumbnail: thumbnail, size: .init(width: 40, height: 30))
        let count = try await store.clean(retentionDays: 30)
        XCTAssertEqual(count, 1)
        try await store.pruneImages()
        let removedData = try await store.imageData(attachment: try XCTUnwrap(expired.attachment))
        let keptData = try await store.imageData(attachment: try XCTUnwrap(kept.attachment))
        XCTAssertNil(removedData); XCTAssertEqual(keptData, pixels)
    }

    func testFailedImageInsertRollsBackPixelsAndEmptyImagesDoNotEnterAIClassification() async throws {
        let database = try SQLiteConnection(path: directory.appendingPathComponent("test.sqlite").path)
        try database.execute("CREATE TRIGGER fail_image BEFORE INSERT ON memories BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END")
        do {
            _ = try await store.saveImage(Memory(body: ""), png: pixels, thumbnail: thumbnail, size: .init(width: 40, height: 30))
            XCTFail("Failed metadata inserts must not leave orphan pixels")
        } catch {}
        XCTAssertEqual(try database.rows("SELECT count(*) FROM image_attachments").first?.first, "0")
        try database.execute("DROP TRIGGER fail_image")
        _ = try await store.saveImage(Memory(body: ""), png: pixels, thumbnail: thumbnail, size: .init(width: 40, height: 30))
        let pending = try await store.pendingClassification()
        XCTAssertTrue(pending.isEmpty)
    }

    func testLocalImageOutboxDoesNotBlockTextSync() async throws {
        for _ in 0..<105 { try await store.save(Memory(body: "", kind: .image)) }
        let text = Memory(body: "sync this note")
        try await store.save(text)
        let pending = try await store.syncPending(limit: 10)
        XCTAssertTrue(pending.contains { $0.id == text.id })
        XCTAssertEqual(pending.filter { $0.kind == .memory }.map(\.id), [text.id])
    }
}
