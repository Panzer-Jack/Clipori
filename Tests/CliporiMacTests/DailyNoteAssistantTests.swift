import XCTest
import Combine
@testable import CliporiCore
@testable import CliporiMac

final class DailyNoteAssistantTests: XCTestCase {
    @MainActor
    func testReviewedAIAddsToLatestManualContentWithoutOverwritingIt() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("memory.sqlite"))
        try await seed(store)
        let model = try makeModel(directory)
        await model.refreshToday()
        let id = try XCTUnwrap(model.addItem(title: "SDK"))
        model.updateItem(id) { $0.isPinned = true; $0.note = "手写安排" }
        let assistant = DailyNoteAssistant(store: store) { context, _ in
            [Self.suggestion(context, target: id)]
        }
        assistant.start(for: try XCTUnwrap(model.note))
        await finished(assistant)
        XCTAssertEqual(model.note?.items[0].tasks.count, 0, "Generation alone does not change the page")
        XCTAssertEqual(assistant.selected.count, 1)
        model.updateItem(id) { $0.title = "用户的新标题" }
        XCTAssertTrue(assistant.apply(to: model))
        XCTAssertFalse(assistant.isPresented)
        XCTAssertEqual(model.note?.items[0].title, "用户的新标题")
        XCTAssertEqual(model.note?.items[0].note, "手写安排")
        XCTAssertTrue(model.note?.items[0].isPinned == true)
        XCTAssertEqual(model.note?.items[0].tasks.first?.title, "完成上报测试")
        let saved = await model.flush(); XCTAssertTrue(saved)
    }

    @MainActor
    func testUnselectedSuggestionsAreNotAddedAndAnotherDateRejectsResult() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("memory.sqlite"))
        try await seed(store)
        let model = try makeModel(directory)
        await model.refreshToday()
        let assistant = DailyNoteAssistant(store: store) { context, _ in [Self.suggestion(context)] }
        assistant.start(for: try XCTUnwrap(model.note))
        await finished(assistant)
        assistant.selected = []
        XCTAssertFalse(assistant.apply(to: model)); XCTAssertTrue(model.note?.items.isEmpty == true)
        assistant.selected = Set(assistant.suggestions.map(\.id))
        let daily = try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite"))
        _ = try await daily.ensureDay("2026-10-13")
        await model.selectDay("2026-10-13")
        XCTAssertFalse(assistant.apply(to: model)); XCTAssertTrue(model.note?.items.isEmpty == true)
        XCTAssertNotNil(assistant.message)
    }

    @MainActor
    func testCancellationDiscardsLateResponsesEvenWhenTransportIgnoresCancellation() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("memory.sqlite"))
        try await seed(store)
        let started = expectation(description: "request started")
        var continuation: CheckedContinuation<[DailyNoteSuggestion], Never>?
        var context: DailyClipboardContext?
        let assistant = DailyNoteAssistant(store: store) { input, _ in
            context = input
            return await withCheckedContinuation { continuation = $0; started.fulfill() }
        }
        assistant.start(for: DailyNote(day: "2026-10-14"))
        await fulfillment(of: [started], timeout: 3)
        assistant.dismiss()
        continuation?.resume(returning: [Self.suggestion(try XCTUnwrap(context))])
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(assistant.isGenerating); XCTAssertFalse(assistant.isPresented)
        XCTAssertTrue(assistant.suggestions.isEmpty)
    }

    @MainActor
    func testDeletedClipboardRecordsCannotBeReintroducedByAResponse() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("memory.sqlite"))
        try await seed(store)
        let assistant = DailyNoteAssistant(store: store) { context, _ in
            try await store.delete(id: context.sources[0].id)
            return [Self.suggestion(context)]
        }
        assistant.start(for: DailyNote(day: "2026-10-14"))
        await finished(assistant)
        XCTAssertTrue(assistant.suggestions.isEmpty)
        XCTAssertNotNil(assistant.message)
    }

    @MainActor
    func testNoSourcesDoesNotCallAIAndConfigurationFailuresAllowRetry() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("memory.sqlite"))
        var calls = 0
        let assistant = DailyNoteAssistant(store: store) { context, _ in
            calls += 1
            if calls == 1 { throw AIError.configuration("test: missing configuration") }
            return [Self.suggestion(context)]
        }
        assistant.start(for: DailyNote(day: "2026-10-14"))
        await finished(assistant)
        XCTAssertEqual(calls, 0); XCTAssertNotNil(assistant.message)
        try await seed(store)
        assistant.start(for: DailyNote(day: "2026-10-14"))
        await finished(assistant)
        XCTAssertEqual(calls, 1); XCTAssertTrue(assistant.needsConfiguration)
        assistant.start(for: DailyNote(day: "2026-10-14"))
        await finished(assistant)
        XCTAssertEqual(calls, 2); XCTAssertFalse(assistant.needsConfiguration)
        XCTAssertEqual(assistant.suggestions.count, 1)
    }

    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("DailyAssistant-\(UUID())") }
    private func seed(_ store: MemoryStore) async throws {
        try await store.save(Memory(body: "SDK 明天需要完成上报测试", source: "Chat", now: DailyNoteDay.date(for: "2026-10-14")!))
    }
    @MainActor private func makeModel(_ directory: URL) throws -> DailyNotesModel {
        DailyNotesModel(store: try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite")), now: { DailyNoteDay.date(for: "2026-10-14")! })
    }
    private static func suggestion(_ context: DailyClipboardContext, target: UUID? = nil) -> DailyNoteSuggestion {
        let source = context.sources[0]
        let evidence = [DailyNoteEvidence(memoryID: source.id, quote: source.content, app: source.app)]
        var task = DailyTask(title: "完成上报测试"); task.evidence = evidence
        return DailyNoteSuggestion(targetItemID: target, title: "SDK", tasks: [task], evidence: evidence)
    }
    @MainActor private func finished(_ assistant: DailyNoteAssistant) async {
        let done = expectation(description: "AI finished")
        let subscription = assistant.$isGenerating.filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
        await fulfillment(of: [done], timeout: 3)
        withExtendedLifetime(subscription) {}
    }
}
