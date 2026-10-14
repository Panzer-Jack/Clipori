import XCTest
@testable import CliporiCore

final class DailyNoteStoreTests: XCTestCase {
    private var directory: URL!
    private var store: DailyNoteStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiDaily-\(UUID())")
        store = try DailyNoteStore(url: directory.appendingPathComponent("daily-notes.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: directory) }

    func testOnlyUnfinishedPinnedItemsCarryWithTheirFullProgress() async throws {
        var today = try await store.ensureDay("2026-10-14")
        let active = DailyItem(title: "SDK", isPinned: true, tasks: [
            DailyTask(title: "测试", isCompleted: true), DailyTask(title: "发布")
        ])
        today.items = [DailyItem(title: "临时工作"), active,
                       DailyItem(title: "全部完成", isPinned: true, tasks: [DailyTask(title: "结束", isCompleted: true)]),
                       DailyItem(title: "独立事项", isPinned: true),
                       DailyItem(title: "独立事项完成", isPinned: true, isCompleted: true)]
        try await store.save(today)
        var next = try await store.ensureDay("2026-10-15")
        XCTAssertEqual(next.items.map(\.title), ["SDK", "独立事项"])
        XCTAssertEqual(next.items.first, active)
        next.items[0].tasks[1].isCompleted = true
        next.items[1].isCompleted = true
        try await store.save(next)
        let third = try await store.ensureDay("2026-10-16")
        XCTAssertTrue(third.items.isEmpty)
        let yesterday = try await store.note(on: today.day)
        XCTAssertEqual(yesterday, today, "Completing today's tasks must not mutate historical pages")
        let completionDay = try await store.note(on: next.day)
        XCTAssertEqual(completionDay, next, "Completed items stay on their completion day")
    }

    func testUnpinningAndReopeningCompletedTasksBeforeRollover() async throws {
        var page = try await store.ensureDay("2026-10-14")
        page.items = [DailyItem(title: "取消 pin", isPinned: true),
                      DailyItem(title: "重新打开", isPinned: true, tasks: [DailyTask(title: "任务", isCompleted: true)])]
        try await store.save(page)
        page.items[0].isPinned = false
        page.items[1].tasks[0].isCompleted = false
        try await store.save(page)
        let next = try await store.ensureDay("2026-10-15")
        XCTAssertEqual(next.items.map(\.title), ["重新打开"])
    }

    func testMissedDaysAreGeneratedInOrderAndPersistAfterReopen() async throws {
        var page = try await store.ensureDay("2026-12-30")
        page.items = [DailyItem(title: "跨年继续", note: "https://example.com", isPinned: true), DailyItem(title: "只在当天")]
        try await store.save(page)
        let january = try await store.ensureDay("2027-01-02")
        XCTAssertEqual(january.items, [page.items[0]])
        let reopened = try DailyNoteStore(url: directory.appendingPathComponent("daily-notes.sqlite"))
        let days = try await reopened.days()
        XCTAssertEqual(days, ["2027-01-02", "2027-01-01", "2026-12-31", "2026-12-30"])
        let persisted = try await reopened.note(on: "2027-01-01")
        XCTAssertEqual(persisted?.items, january.items)
    }

    func testHistoricalEditsNeverRegenerateAnExistingDay() async throws {
        var original = try await store.ensureDay("2026-10-14")
        original.items = [DailyItem(title: "旧标题", isPinned: true)]
        try await store.save(original)
        let next = try await store.ensureDay("2026-10-15")
        original.items[0].title = "只修改往期"; original.items[0].isPinned = false
        try await store.save(original)
        let unchanged = try await store.ensureDay("2026-10-15")
        XCTAssertEqual(unchanged, next)
        let future = try await store.ensureDay("2026-10-16")
        XCTAssertEqual(future.items, next.items)
    }

    func testConcurrentGenerationProducesExactlyOnePagePerDay() async throws {
        var page = try await store.ensureDay("2026-10-14")
        page.items = [DailyItem(title: "保留一次", isPinned: true)]
        try await store.save(page)
        async let first = store.ensureDay("2026-10-16")
        async let second = store.ensureDay("2026-10-16")
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b); XCTAssertEqual(a.items.count, 1)
        let days = try await store.days()
        XCTAssertEqual(days.count, 3)
    }

    func testGenerationFailureRollsBackAllMissingDays() async throws {
        _ = try await store.ensureDay("2026-10-14")
        let db = try SQLiteConnection(path: directory.appendingPathComponent("daily-notes.sqlite").path)
        try db.execute("CREATE TRIGGER fail_daily BEFORE INSERT ON daily_notes WHEN NEW.day='2026-10-16' BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END")
        do { _ = try await store.ensureDay("2026-10-17"); XCTFail("Expected write failure") } catch {}
        let days = try await store.days()
        XCTAssertEqual(days, ["2026-10-14"])
        try db.execute("DROP TRIGGER fail_daily")
        let recovered = try await store.ensureDay("2026-10-17")
        XCTAssertEqual(recovered.day, "2026-10-17")
    }

    func testClipboardCleanupDoesNotDeleteDailyNotes() async throws {
        var page = try await store.ensureDay("2026-01-01")
        page.items = [DailyItem(title: "永久保存每日记录")]
        try await store.save(page)
        let clipboard = try MemoryStore(url: directory.appendingPathComponent("clipori.sqlite"))
        try await clipboard.save(Memory(body: "旧剪贴板", now: .distantPast))
        try await clipboard.clean(retentionDays: 1)
        try await clipboard.deleteAllMemories()
        let retained = try await store.note(on: page.day)
        XCTAssertEqual(retained, page)
    }

    func testDateKeysHandleTimeZonesLeapYearsAndDaylightSaving() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T16:30:00Z"))
        XCTAssertEqual(DailyNoteDay.key(for: instant, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "2026-10-15")
        XCTAssertEqual(DailyNoteDay.key(for: instant, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-10-14")
        XCTAssertEqual(DailyNoteDay.next(after: "2028-02-28"), "2028-02-29")
        XCTAssertEqual(DailyNoteDay.next(after: "2028-02-29"), "2028-03-01")
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let start = try XCTUnwrap(DailyNoteDay.date(for: "2026-03-08", timeZone: zone))
        let next = try XCTUnwrap(DailyNoteDay.date(for: "2026-03-09", timeZone: zone))
        XCTAssertEqual(next.timeIntervalSince(start), 23 * 3600)
        XCTAssertEqual(DailyNoteDay.next(after: "2026-03-08"), "2026-03-09")
        XCTAssertNil(DailyNoteDay.date(for: "2026-02-30"))
        XCTAssertNil(DailyNoteDay.date(for: "2026-2-3"))
    }
}
