import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class CategoryDropTests: XCTestCase {
    func testNativeDropHighlightsOnlyValidTargetsAndSavesTheWholeGroup() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiDrop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let records = [Memory(body: "first"), Memory(body: "second")]
        for record in records { try await model.store.save(record) }
        model.memories = records; model.categories = MemoryCategory.defaults
        model.select(records[0].id)
        model.selectFromPointer(records[1].id, modifiers: .command)
        let drag = try XCTUnwrap(model.beginDragging(records[0].id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([drag.pasteboardItem])
        let info = TestDraggingInfo(pasteboard: pasteboard)
        let target = CategoryDropView(frame: NSRect(x: 0, y: 0, width: 90, height: 30))
        target.model = model
        var highlights: [Bool] = []
        target.onTargetChange = { highlights.append($0) }
        XCTAssertTrue(target.registeredDraggedTypes.contains(MemoryDrag.pasteboardType))
        XCTAssertEqual(target.draggingEntered(info), [], "All memories is not an assignable category")
        target.categoryID = model.categories[0].id
        XCTAssertEqual(target.draggingEntered(info), .move)
        XCTAssertEqual(highlights, [true])
        target.draggingExited(info)
        XCTAssertEqual(highlights, [true, false])
        XCTAssertEqual(target.draggingEntered(info), .move)
        XCTAssertTrue(target.prepareForDragOperation(info))
        XCTAssertTrue(target.performDragOperation(info))
        XCTAssertNil(model.memoryDrag)
        XCTAssertEqual(highlights.last, false)
        for _ in 0..<30 {
            if model.memories.allSatisfy({ $0.categoryID == target.categoryID }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let saved = try await model.store.list(categoryID: target.categoryID)
        XCTAssertEqual(Set(saved.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(target.draggingEntered(info), [], "A completed session token cannot be reused")
        _ = model.beginDragging(records[0].id)
        XCTAssertEqual(target.draggingEntered(info), [], "An older token cannot target a new selection")
    }
}

@MainActor
private final class TestDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingSource: Any? = CardPointerView()
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
