import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class MultiSelectionTests: XCTestCase {
    private var directory: URL!
    private var model: AppModel!
    override func setUpWithError() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiSelection-\(UUID())")
        model = try AppModel(directory: directory, preview: true)
        model.memories = (0..<6).map { Memory(body: "Memory \($0)") }
        model.categories = MemoryCategory.defaults
    }
    override func tearDownWithError() throws {
        model = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testCommandTogglesAndShiftExtendsFromAnAnchorInBothDirections() {
        let ids = model.memories.map(\.id)
        model.selectFromPointer(ids[1], modifiers: [])
        model.selectFromPointer(ids[3], modifiers: .command)
        XCTAssertEqual(model.selectionIDs, Set([ids[1], ids[3]]))
        model.selectFromPointer(ids[3], modifiers: .command)
        XCTAssertEqual(model.selectionIDs, [ids[1]])
        model.selectFromPointer(ids[4], modifiers: .shift)
        XCTAssertEqual(model.selectionIDs, Set(ids[1...4]))
        model.selectFromPointer(ids[0], modifiers: .shift)
        XCTAssertEqual(model.selectionIDs, Set(ids[0...1]))
        model.selectFromPointer(ids[5], modifiers: [.command, .shift])
        XCTAssertEqual(model.selectionIDs, Set(ids))
        XCTAssertNil(model.selectionToReveal, "Mouse selection must not move the cards")
    }

    func testPlainClicksCopyOnlyTheCurrentCardWhileMultiSelectionAndDraggingDoNotCopy() throws {
        let records = model.memories
        var copies: [UUID] = []
        model.onCopy = { copies.append($0.id) }
        for record in records.prefix(2) {
            model.selectFromPointer(record.id, modifiers: [])
            let beforeRelease = copies.count
            model.clickCard(record.id)
            XCTAssertEqual(copies.count, beforeRelease + 1)
            XCTAssertEqual(copies.last, record.id)
            XCTAssertEqual(model.selectionIDs, [record.id])
        }
        XCTAssertEqual(copies, records.prefix(2).map(\.id))
        model.selectFromPointer(records[3].id, modifiers: .command)
        model.clickCard(records[3].id, modifiers: .command)
        model.selectFromPointer(records[5].id, modifiers: .shift)
        model.clickCard(records[5].id, modifiers: .shift)
        XCTAssertEqual(model.selectionIDs, Set(records[3...5].map(\.id)))
        model.selectFromPointer(records[4].id, modifiers: [])
        XCTAssertEqual(try XCTUnwrap(model.beginDragging(records[4].id)).ids, records[3...5].map(\.id))
        model.endDragging()
        XCTAssertEqual(copies.count, 2, "Modifier clicks, mouse-down and dragging only select")
        model.clickCard(records[4].id)
        XCTAssertEqual(model.selectionIDs, [records[4].id])
        XCTAssertEqual(copies, [records[0].id, records[1].id, records[4].id])
        XCTAssertNil(model.selectionToReveal)
        model.clickCard(UUID())
        XCTAssertEqual(copies.count, 3, "A disappeared card must not copy a different selection")
    }

    func testPressKeepsTheWholeGroupForDragButPlainClickCollapsesIt() throws {
        let ids = model.memories.map(\.id)
        model.select(ids[0])
        model.selectFromPointer(ids[2], modifiers: .command)
        model.selectFromPointer(ids[0], modifiers: [])
        XCTAssertEqual(model.selectionIDs, Set([ids[0], ids[2]]))
        let drag = try XCTUnwrap(model.beginDragging(ids[0]))
        XCTAssertEqual(drag.ids, [ids[0], ids[2]])
        XCTAssertEqual(drag.pasteboardItem.types, [MemoryDrag.pasteboardType])
        XCTAssertEqual(drag.pasteboardItem.string(forType: MemoryDrag.pasteboardType), drag.token.uuidString)
        model.endDragging()
        XCTAssertNil(model.memoryDrag)
        XCTAssertEqual(model.selectionIDs, Set([ids[0], ids[2]]), "A cancelled drag retains the group")
        model.clickCard(ids[0])
        XCTAssertEqual(model.selectionIDs, [ids[0]])
        model.selectFromPointer(ids[4], modifiers: [])
        XCTAssertEqual(model.selectionIDs, [ids[4]], "An unselected card responds on mouse-down")
    }

    func testSelectionSurvivesPagingAndReloadButDoesNotLeakIntoAnotherFilter() async throws {
        let records = model.memories
        for record in records { try await model.store.save(record) }
        model.select(records[0].id)
        model.selectFromPointer(records[2].id, modifiers: .command)
        await model.reload()
        XCTAssertEqual(model.selectionIDs, Set([records[0].id, records[2].id]))
        try await model.store.delete(id: records[0].id)
        await model.reload()
        XCTAssertEqual(model.selectionIDs, [records[2].id])
        model.query = "Memory 5"
        await model.reload()
        XCTAssertEqual(model.selectionIDs, [records[5].id])
        XCTAssertEqual(model.selectionID, records[5].id)
        model.moveSelection(1)
        XCTAssertEqual(model.selectionIDs, [records[5].id])
    }

    func testMovingAGroupPreservesLoadedPagesAndSelectionInAllMemories() async throws {
        let records = (0..<100).map { Memory(body: "Loaded \($0)") }
        for record in records { try await model.store.save(record) }
        model.memories = records
        model.select(records[82].id)
        model.selectFromPointer(records[96].id, modifiers: .command)
        await model.assign(ids: [records[82].id, records[96].id], to: model.categories[0].id)
        XCTAssertEqual(model.memories.map(\.id), records.map(\.id))
        XCTAssertEqual(model.selectionIDs, Set([records[82].id, records[96].id]))
        XCTAssertEqual(model.memories[82].categoryID, model.categories[0].id)
        XCTAssertNil(model.selectionToReveal)
    }

    func testDroppingOutsideACategoryDoesNothingAndMovingFromAFilteredCategoryRemovesCards() async throws {
        let source = model.categories[0].id, target = model.categories[1].id
        var records = model.memories
        for index in records.indices {
            records[index].categoryID = source
            try await model.store.save(records[index])
        }
        model.categoryID = source
        await model.reload()
        model.select(records[0].id)
        model.selectFromPointer(records[1].id, modifiers: .command)
        _ = model.beginDragging(records[0].id)
        XCTAssertFalse(model.dropMemories(to: UUID()))
        model.endDragging()
        let unchanged = try await model.store.record(id: records[0].id)
        XCTAssertEqual(unchanged?.categoryID, source)
        await model.assign(ids: [records[0].id, records[1].id], to: target)
        XCTAssertEqual(model.displayed.count, 4)
        XCTAssertFalse(model.displayed.contains { [records[0].id, records[1].id].contains($0.id) })
        XCTAssertTrue(model.selectionIDs.isSubset(of: Set(model.displayed.map(\.id))))
        XCTAssertNil(model.errorMessage)
    }
}
