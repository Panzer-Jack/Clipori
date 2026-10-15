import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class ClipboardHistoryModelTests: XCTestCase {
    func testCardCopyDefersVisibleOrderAcrossReloadsUntilNextPresentation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let first = Memory(body: "first", now: Date().addingTimeInterval(-2))
        let second = Memory(body: "second", now: Date().addingTimeInterval(-1))
        await model.accept(first); await model.accept(second)
        model.isVisible = true
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(model: model, pasteboard: board)
        var requestedCopy: Memory?
        model.onCopy = { requestedCopy = $0 }
        model.clickCard(first.id)
        let copied = await monitor.copy(try XCTUnwrap(requestedCopy))
        XCTAssertTrue(copied)
        XCTAssertEqual(board.string(forType: .string), first.body)
        XCTAssertEqual(model.memories, [second, first])
        XCTAssertEqual(model.selectionID, first.id)
        XCTAssertNil(model.selectionToReveal)
        await model.reload()
        XCTAssertEqual(model.memories, [second, first], "Background refresh must not move the card under a second click")
        let persisted = try await model.store.list()
        XCTAssertEqual(persisted, [first, second])
        let reopened = try MemoryStore(url: directory.appendingPathComponent("clipori.sqlite"))
        let persistedAfterRestart = try await reopened.list()
        XCTAssertEqual(persistedAfterRestart, persisted)
        model.isVisible = false
        model.isVisible = true
        await model.refreshForPresentation()
        XCTAssertEqual(model.memories, [first, second])
        XCTAssertEqual(model.selectionToReveal, first.id)
        XCTAssertEqual(model.totalCount, 2)
    }

    func testDuplicateCapturePromotesWithoutAddingOrChangingUserMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        var first = Memory(title: "my title", body: "first", now: Date().addingTimeInterval(-2))
        first.keepForever = true
        let second = Memory(body: "second", now: Date().addingTimeInterval(-1))
        await model.accept(first); await model.accept(second)
        model.isVisible = true; model.select(second.id)
        await model.accept(Memory(body: first.body, source: "another app"))
        XCTAssertEqual(model.totalCount, 2)
        XCTAssertEqual(model.memories, [first, second])
        XCTAssertEqual(model.pendingIncoming, 0)
        XCTAssertEqual(model.selectionID, second.id)
        let original = try await model.store.record(id: first.id)
        XCTAssertEqual(original, first)
        model.preferences.moveToFrontAfterUse = false
        await model.accept(Memory(body: second.body))
        await model.reload()
        XCTAssertEqual(model.memories, [first, second])
    }

    func testCopyPromotionHonorsPreferenceAndDoesNotResurrectDeletedRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let first = Memory(body: "first", now: Date().addingTimeInterval(-2))
        let second = Memory(body: "second", now: Date().addingTimeInterval(-1))
        await model.accept(first); await model.accept(second)
        model.preferences.moveToFrontAfterUse = false
        await model.didUse(first)
        await model.refreshForPresentation()
        XCTAssertEqual(model.memories, [second, first])
        model.preferences.moveToFrontAfterUse = true
        await model.didUse(first)
        await model.refreshForPresentation()
        XCTAssertEqual(model.memories, [first, second])
        XCTAssertEqual(model.selectionToReveal, first.id)
        try await model.store.delete(id: first.id)
        await model.didUse(first)
        let count = try await model.store.count()
        XCTAssertEqual(count, 1)
    }

    func testRepeatedCardUsesAndNewCaptureKeepCurrentOrderButReopenWithLatestUseFirst() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let first = Memory(body: "first", now: Date().addingTimeInterval(-3))
        let second = Memory(body: "second", now: Date().addingTimeInterval(-2))
        let third = Memory(body: "third", now: Date().addingTimeInterval(-1))
        for record in [first, second, third] { await model.accept(record) }
        model.isVisible = true
        model.aiResults = [third, second, first]
        await model.didUse(second)
        await model.didUse(first)
        await model.reload()
        XCTAssertEqual(model.memories, [third, second, first])
        XCTAssertEqual(model.aiResults, [third, second, first])
        await model.refreshForPresentation()
        XCTAssertEqual(model.memories, [first, second, third])
        XCTAssertEqual(model.aiResults, [first, second, third])
        model.aiResults = nil
        await model.didUse(third)
        let new = Memory(body: "new")
        await model.accept(new)
        XCTAssertEqual(model.memories, [new, first, second, third])
        await model.accept(Memory(body: second.body))
        XCTAssertEqual(model.memories.first?.id, second.id)
        await model.refreshForPresentation()
        XCTAssertEqual(model.memories.first?.id, second.id)
    }
}
