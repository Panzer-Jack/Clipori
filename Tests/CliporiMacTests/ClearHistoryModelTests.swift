import XCTest
import AppKit
import CliporiCore
@testable import CliporiMac

final class ClearHistoryModelTests: XCTestCase {
    @MainActor
    func testClearResetsShelfAIUndoAndEditorsThenAllowsNewCopies() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiClearModel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        model.categories = try await model.store.categories()
        let categories = model.categories
        let original = Memory(body: "Old note")
        let undoRecord = Memory(body: "Old deleted note")
        try await model.store.save(original); try await model.store.save(undoRecord)
        await model.reload()
        model.delete(undoRecord)
        for _ in 0..<100 {
            if model.notice == L("记录已删除，可撤销") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.notice, L("记录已删除，可撤销"))
        model.query = "Old"; model.categoryID = categories.first?.id
        model.aiResults = [original]; model.aiAnswer = "Old answer"; model.select(original.id)
        model.pendingIncoming = 3; model.hasMore = true
        _ = model.beginDragging(original.id)
        let editor = EditorModel(record: nil, app: model)
        editor.record.body = "An open draft"; editor.changed()
        model.onPrepareHistoryClear = {
            // Copies arriving during deletion must not immediately refill history.
            await model.accept(Memory(body: "During clear"))
            return await editor.flush()
        }
        var closed = false
        model.onHistoryCleared = { closed = true; editor.discardChanges() }
        let deleted = try await model.clearHistory()
        XCTAssertEqual(deleted, 2); XCTAssertTrue(closed)
        XCTAssertFalse(model.isClearingHistory); XCTAssertEqual(model.totalCount, 0)
        XCTAssertTrue(model.memories.isEmpty); XCTAssertNil(model.aiResults); XCTAssertEqual(model.aiAnswer, "")
        XCTAssertTrue(model.selectionIDs.isEmpty); XCTAssertNil(model.memoryDrag)
        XCTAssertEqual(model.pendingIncoming, 0); XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.query, ""); XCTAssertNil(model.categoryID); XCTAssertEqual(model.categories, categories)
        model.undoDeletion()
        editor.record.body = "Stale window change"; editor.changed()
        let flushed = await editor.flush(); XCTAssertTrue(flushed)
        try await Task.sleep(for: .milliseconds(120))
        let count = try await model.store.count(); XCTAssertEqual(count, 0)
        let newCopy = Memory(body: "A new copy")
        await model.accept(newCopy)
        XCTAssertEqual(model.totalCount, 1)
        let saved = try await model.store.record(id: newCopy.id); XCTAssertEqual(saved, newCopy)
    }

    @MainActor
    func testFailedPreparationKeepsRecordsAndReleasesBusyState() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiClearFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let record = Memory(body: "Keep on failure")
        try await model.store.save(record); await model.reload()
        model.onPrepareHistoryClear = { false }
        var closed = false; model.onHistoryCleared = { closed = true }
        do { try await model.clearHistory(); XCTFail("Must preserve history when a draft cannot be saved") } catch {}
        XCTAssertFalse(model.isClearingHistory); XCTAssertFalse(closed)
        let saved = try await model.store.record(id: record.id)
        XCTAssertEqual(saved, record); XCTAssertEqual(model.memories, [record])
    }
}
