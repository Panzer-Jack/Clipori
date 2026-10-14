import XCTest
@testable import CliporiCore
@testable import CliporiMac

final class DailyNotesModelTests: XCTestCase {
    @MainActor
    func testOverlappingSavesKeepTheLatestEditAndNewTasksResumeCarryover() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyConcurrent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite"))
        let model = DailyNotesModel(store: store, now: { DailyNoteDay.date(for: "2026-10-14")! })
        await model.refreshToday()
        let id = try XCTUnwrap(model.addItem(title: "初稿"))
        model.updateItem(id) { $0.isPinned = true; $0.isCompleted = true }
        var saves: [Task<Bool, Never>] = []
        for index in 0..<20 {
            model.updateItem(id) { $0.title = "版本 \(index)" }
            saves.append(Task { await model.flush() })
            await Task.yield()
        }
        model.updateItem(id) { $0.title = "最后版本" }
        let taskID = try XCTUnwrap(model.addTask(to: id))
        model.updateTask(taskID, in: id) { $0.title = "追加工作" }
        for task in saves { let result = await task.value; XCTAssertTrue(result) }
        let result = await model.flush()
        XCTAssertTrue(result); XCTAssertFalse(model.isDirty)
        let saved = try await store.note(on: "2026-10-14")
        XCTAssertEqual(saved?.items.first?.title, "最后版本")
        XCTAssertEqual(saved?.items.first?.tasks.first?.title, "追加工作")
        let tomorrow = try await store.ensureDay("2026-10-15")
        XCTAssertEqual(tomorrow.items, saved?.items)
    }

    @MainActor
    func testSwitchingDatesFlushesTypingAndPreservesHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyModel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite"))
        _ = try await store.ensureDay("2026-10-13")
        let model = DailyNotesModel(store: store, now: { DailyNoteDay.date(for: "2026-10-14")! })
        await model.refreshToday()
        let id = try XCTUnwrap(model.addItem(title: "新增"))
        for index in 0..<30 { model.updateItem(id) { $0.title = "输入 \(index)" } }
        await model.selectDay("2026-10-13")
        XCTAssertEqual(model.note?.day, "2026-10-13")
        XCTAssertFalse(model.isDirty)
        let saved = try await store.note(on: "2026-10-14")
        XCTAssertEqual(saved?.items.first?.title, "输入 29")
        model.addItem(title: "只修改历史")
        await model.selectDay("2026-10-14")
        XCTAssertEqual(model.note?.items.count, 1)
        XCTAssertEqual(model.note?.items.first?.title, "输入 29")
    }

    @MainActor
    func testMidnightFlushesLatestProgressAndFollowsToday() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyRollover-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite"))
        var day = "2026-10-14"
        let model = DailyNotesModel(store: store, now: { DailyNoteDay.date(for: day)! })
        await model.refreshToday()
        let id = try XCTUnwrap(model.addItem(title: "SDK"))
        model.updateItem(id) { $0.isPinned = true }
        let taskID = try XCTUnwrap(model.addTask(to: id))
        model.updateTask(taskID, in: id) { $0.title = "发布" }
        day = "2026-10-15"
        await model.refreshToday()
        XCTAssertEqual(model.note?.day, day)
        XCTAssertEqual(model.note?.items.first?.tasks.first?.title, "发布")
        model.updateTask(taskID, in: id) { $0.isCompleted = true }
        day = "2026-10-16"
        await model.refreshToday()
        XCTAssertEqual(model.note?.items, [])
        let previous = try await store.note(on: "2026-10-15")
        XCTAssertTrue(previous?.items.first?.completed == true)
        await model.selectDay("2026-10-14")
        day = "2026-10-17"
        await model.refreshToday()
        XCTAssertEqual(model.note?.day, "2026-10-14", "Midnight must not interrupt reading historical pages")
        XCTAssertEqual(model.days.first, day)
    }

    @MainActor
    func testSaveFailureKeepsDraftAndBlocksNavigationUntilRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("daily.sqlite")
        let store = try DailyNoteStore(url: url)
        _ = try await store.ensureDay("2026-10-13")
        let model = DailyNotesModel(store: store, now: { DailyNoteDay.date(for: "2026-10-14")! })
        await model.refreshToday()
        let db = try SQLiteConnection(path: url.path)
        try db.execute("CREATE TRIGGER fail_save BEFORE INSERT ON daily_notes BEGIN SELECT RAISE(ABORT, 'simulated disk full'); END")
        model.addItem(title: "不能丢失")
        await model.selectDay("2026-10-13")
        XCTAssertEqual(model.note?.day, "2026-10-14")
        XCTAssertEqual(model.note?.items.first?.title, "不能丢失")
        XCTAssertNotNil(model.errorMessage); XCTAssertTrue(model.isDirty)
        try db.execute("DROP TRIGGER fail_save")
        await model.selectDay("2026-10-13")
        XCTAssertEqual(model.note?.day, "2026-10-13")
        XCTAssertNil(model.errorMessage)
        let recovered = try await store.note(on: "2026-10-14")
        XCTAssertEqual(recovered?.items.first?.title, "不能丢失")
    }

    @MainActor
    func testOrderingAndDeletionRecoveryPersistWithoutDiscardingLaterEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyOrder-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite"))
        let model = DailyNotesModel(store: store, now: { DailyNoteDay.date(for: "2026-10-14")! })
        await model.refreshToday()
        let a = try XCTUnwrap(model.addItem(title: "A")), b = try XCTUnwrap(model.addItem(title: "B"))
        model.moveItem(b, before: a)
        let first = try XCTUnwrap(model.addTask(to: b)), second = try XCTUnwrap(model.addTask(to: b))
        model.moveTask(second, before: first, in: b)
        model.deleteTask(second, in: b); model.undoDeletion()
        XCTAssertEqual(model.note?.items[0].tasks.map(\.id), [second, first])
        model.deleteItem(a); model.undoDeletion()
        XCTAssertEqual(model.note?.items.map(\.id), [b, a])
        model.deleteItem(a)
        model.updateItem(b) { $0.title = "稍后编辑" }
        XCTAssertNil(model.deletedSnapshot)
        model.undoDeletion()
        let flushed = await model.flush()
        XCTAssertTrue(flushed)
        let saved = try await store.note(on: "2026-10-14")
        XCTAssertEqual(saved?.items.map(\.title), ["稍后编辑"])
        XCTAssertEqual(saved?.items.first?.tasks.map(\.id), [second, first])
    }
}
