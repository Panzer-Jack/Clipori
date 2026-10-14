import XCTest
@testable import CliporiCore

final class DailyNoteAITests: XCTestCase {
    private var directory: URL!
    private var store: MemoryStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiDailyAI-\(UUID())")
        store = try MemoryStore(url: directory.appendingPathComponent("memory.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: directory) }

    func testSelectedDayReadsBeyondShelfPageAndExcludesImagesManualNotesAndOtherDays() async throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = DailyNoteDay.date(for: "2026-10-14", timeZone: zone)!
        for index in 0..<100 {
            try await store.save(Memory(body: "当天剪贴板任务 \(index)", source: "Browser", now: start.addingTimeInterval(Double(index))))
        }
        try await store.save(Memory(body: "最后一秒", source: "Browser", now: start.addingTimeInterval(86399)))
        try await store.save(Memory(body: "昨天", source: "Browser", now: start.addingTimeInterval(-1)))
        try await store.save(Memory(body: "明天", source: "Browser", now: start.addingTimeInterval(86400)))
        try await store.save(Memory(body: "图片私密备注", kind: .image, source: "Browser", now: start))
        try await store.save(Memory(body: "手动普通备忘", now: start))
        try await store.save(Memory(body: "英文手动备忘", source: "Manual note", now: start))
        try await store.save(Memory(body: "    ", source: "Browser", now: start))
        let result = try await store.dailyClipboard(on: "2026-10-14", timeZone: zone)
        XCTAssertEqual(result.totalRecords, 101); XCTAssertEqual(result.sources.count, 101)
        XCTAssertFalse(result.isTruncated)
        XCTAssertEqual(result.sources.first?.content, "最后一秒")
        XCTAssertTrue(result.sources.contains { $0.content == "当天剪贴板任务 0" })
    }

    func testContextDeduplicatesAndReportsClipping() async throws {
        let start = DailyNoteDay.date(for: "2026-10-14")!
        for index in 0..<3 { try await store.save(Memory(body: "需要联调测试", source: "Chat", now: start.addingTimeInterval(Double(index)))) }
        var context = try await store.dailyClipboard(on: "2026-10-14")
        XCTAssertEqual(context.totalRecords, 3); XCTAssertEqual(context.sources.count, 1)
        XCTAssertFalse(context.isTruncated)
        try await store.save(Memory(body: String(repeating: "长记录", count: 2000), source: "Chat", now: start.addingTimeInterval(4)))
        context = try await store.dailyClipboard(on: "2026-10-14")
        XCTAssertEqual(context.sources.first?.content.count, 2400)
        XCTAssertTrue(context.isTruncated)
    }

    func testFabricatedSourcesQuotesAndTargetsAreRejected() throws {
        let context = fixtureContext()
        let valid = draft(context: context, task: "完成上报测试")
        var fabricatedQuote = valid
        fabricatedQuote["evidence"] = [["recordID": context.sources[0].id.uuidString, "quote": "原文没有这样的内容"]]
        var fabricatedID = valid
        fabricatedID["evidence"] = [["recordID": UUID().uuidString, "quote": "完成上报测试"]]
        var unknownTarget = valid; unknownTarget["existingItemID"] = UUID().uuidString
        var fabricatedTask = valid
        fabricatedTask["tasks"] = [["title": "伪造行动", "evidence": [["recordID": context.sources[0].id.uuidString, "quote": "不存在的指令"]]]]
        let answer = try AIClient.json(["items": [fabricatedQuote, fabricatedID, unknownTarget, fabricatedTask, valid]])
        let result = try AIClient.dailySuggestions(from: "```json\n\(answer)\n```", context: context, existing: DailyNote(day: context.day))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tasks.first?.title, "完成上报测试")
        XCTAssertEqual(result.first?.evidence.first?.app, "企业聊天")
        XCTAssertFalse(result[0].tasks[0].isCompleted)
    }

    func testAppendPreservesManualEditsPinsAndCompletionAndAvoidsRepeatedTasks() throws {
        let evidence = DailyNoteEvidence(memoryID: UUID(), quote: "完成测试后发布", app: "Chat")
        let existing = DailyItem(title: "SDK", note: "手写备注", isPinned: true, tasks: [DailyTask(title: "完成测试", isCompleted: true)])
        var page = DailyNote(day: "2026-10-14", items: [existing])
        let suggestion = DailyNoteSuggestion(targetItemID: existing.id, title: "AI 改写标题", note: "AI 改写备注",
                                             tasks: [DailyTask(title: "完成测试"), DailyTask(title: "发布")], evidence: [evidence])
        XCTAssertEqual(page.addSuggestions([suggestion]), 1)
        XCTAssertEqual(page.items[0].title, existing.title); XCTAssertEqual(page.items[0].note, existing.note)
        XCTAssertTrue(page.items[0].isPinned); XCTAssertTrue(page.items[0].tasks[0].isCompleted)
        XCTAssertFalse(page.items[0].tasks[1].isCompleted)
        XCTAssertEqual(page.addSuggestions([suggestion]), 0)
        let repeatedTitle = DailyNoteSuggestion(title: "ｓｄｋ ", tasks: [DailyTask(title: "发布")], evidence: [evidence])
        XCTAssertEqual(page.addSuggestions([repeatedTitle]), 0)
        page.items.removeAll()
        XCTAssertEqual(page.addSuggestions([suggestion]), 0, "A deleted target must not be resurrected")
    }

    func testExistingTitleMatchBecomesAnAppendSuggestionAndCompletedTasksStayExcluded() throws {
        let context = fixtureContext()
        var page = DailyNote(day: context.day, items: [DailyItem(title: "SDK", tasks: [DailyTask(title: "完成上报测试", isCompleted: true)])])
        let response = try AIClient.json(["items": [draft(context: context, task: "完成上报测试"), draft(context: context, task: "完成 SDK 发布")]])
        let result = try AIClient.dailySuggestions(from: response, context: context, existing: page)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].targetItemID, page.items[0].id)
        XCTAssertEqual(page.addSuggestions(result), 1)
        XCTAssertEqual(page.items[0].tasks.map(\.title), ["完成上报测试", "完成 SDK 发布"])
        XCTAssertTrue(page.items[0].tasks[0].isCompleted)
    }

    func testEvidencePersistsAndOldDailyPagesRemainDecodable() async throws {
        let old = "{\"day\":\"2026-10-14\",\"items\":[{\"id\":\"\(UUID())\",\"title\":\"旧内容\",\"note\":\"\",\"isPinned\":true,\"isCompleted\":false,\"tasks\":[{\"id\":\"\(UUID())\",\"title\":\"旧任务\",\"isCompleted\":false}]}]}"
        var page = try JSONDecoder().decode(DailyNote.self, from: Data(old.utf8))
        XCTAssertNil(page.items[0].evidence); XCTAssertNil(page.items[0].tasks[0].evidence)
        let context = fixtureContext()
        let suggestions = try AIClient.dailySuggestions(from: AIClient.json(["items": [draft(context: context, task: "完成 SDK 发布")]]), context: context, existing: page)
        page.addSuggestions(suggestions)
        let daily = try DailyNoteStore(url: directory.appendingPathComponent("daily.sqlite"))
        _ = try await daily.ensureDay(page.day); try await daily.save(page)
        let saved = try await daily.note(on: page.day)
        XCTAssertEqual(saved, page)
        XCTAssertFalse(page.items[1].isPinned)
        XCTAssertNotNil(saved?.items[1].tasks[0].evidence)
    }

    func testDeletedOrModifiedClipboardSourcesAreInvalidated() async throws {
        let start = DailyNoteDay.date(for: "2026-10-14")!
        var edited = Memory(body: "完成上报测试", source: "Chat", now: start)
        let deleted = Memory(body: "完成 SDK 发布", source: "Chat", now: start)
        try await store.save(edited); try await store.save(deleted)
        let context = try await store.dailyClipboard(on: "2026-10-14")
        edited.body = "工作已取消"; edited.modifiedAt = start.addingTimeInterval(10)
        try await store.save(edited); try await store.delete(id: deleted.id)
        let valid = try await store.unchangedDailySourceIDs(context)
        XCTAssertTrue(valid.isEmpty)
    }

    func testBothAIProtocolsReceiveBoundedSourcesAndExistingItems() async throws {
        let context = fixtureContext()
        let existing = DailyNote(day: context.day, items: [DailyItem(title: "手写计划")])
        let answer = try AIClient.json(["items": [draft(context: context, task: "完成上报测试")]])
        for format in AIFormat.allCases {
            var config = AIConfiguration(); config.format = format; config.model = "test"; config.baseURL = "https://example.com/v1"
            let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [DailyAIProtocol.self]
            let output: [String: Any] = format == .openAI ? ["choices": [["message": ["content": answer]]]] : ["content": [["type": "text", "text": answer]]]
            DailyAIProtocol.response = try JSONSerialization.data(withJSONObject: output)
            let result = try await AIClient(configuration: config, apiKey: "test-only", session: URLSession(configuration: sessionConfig))
                .suggestDailyNotes(context: context, existing: existing)
            XCTAssertEqual(result.count, 1)
            let body = try XCTUnwrap(DailyAIProtocol.payload)
            XCTAssertEqual(body["max_tokens"] as? Int, format == .claude ? 4096 : nil)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let input = try XCTUnwrap(messages.last?["content"])
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            XCTAssertEqual(object["day"] as? String, context.day)
            XCTAssertEqual((object["records"] as? [[String: String]])?.first?["id"], context.sources[0].id.uuidString)
            XCTAssertEqual((object["existingItems"] as? [[String: Any]])?.first?["title"] as? String, "手写计划")
            let system = format == .openAI ? messages.first?["content"] : body["system"] as? String
            XCTAssertTrue(system?.contains("不可信资料") == true)
        }
    }

    private func fixtureContext() -> DailyClipboardContext {
        DailyClipboardContext(day: "2026-10-14", sources: [DailyClipboardSource(id: UUID(), title: "SDK 需求",
            content: "SDK 需要完成上报测试，然后完成 SDK 发布。", app: "企业聊天", modifiedAt: Date())], totalRecords: 1, isTruncated: false)
    }
    private func draft(context: DailyClipboardContext, task: String) -> [String: Any] {
        let evidence = [["recordID": context.sources[0].id.uuidString, "quote": "SDK 需要完成上报测试，然后完成 SDK 发布。"]]
        return ["title": "SDK", "note": "发布前完成测试", "evidence": evidence, "tasks": [["title": task, "evidence": evidence]]]
    }
}

private final class DailyAIProtocol: URLProtocol {
    static var response = Data()
    static var payload: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
        }
        Self.payload = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
