import XCTest
@testable import CliporiCore

final class HistoryScaleTests: XCTestCase {
    func testLargeHistoryKeepsPagingAndRetrievalBounded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiScale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(url: directory.appendingPathComponent("test.sqlite"))
        for index in 0..<10_000 {
            let body = index == 321 ? "青山食堂：花园路18号，周末聚餐" : "第\(index)条项目备忘：交互设计、代码和日常灵感。"
            try await store.save(Memory(body: body, now: Date(timeIntervalSince1970: Double(index) * 60)))
        }
        let start = Date()
        let page = try await store.list(limit: 80)
        let keyword = try await store.list(query: "青山")
        let aiCandidates = try await store.candidates(plan: SearchPlan(keywords: ["食堂", "聚餐"]))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(page.count, 80)
        XCTAssertEqual(keyword.count, 1)
        XCTAssertEqual(aiCandidates.first?.id, keyword.first?.id)
        XCTAssertLessThan(elapsed, 1.0, "Initial page + keyword + indexed retrieval should stay responsive with 10k records")
        print("Clipori 10k history: page + keyword + AI retrieval = \(String(format: "%.1f", elapsed * 1000)) ms")
    }
}
