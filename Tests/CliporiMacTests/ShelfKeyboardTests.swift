import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class ShelfKeyboardTests: XCTestCase {
    func testImagePasteKeepsPlainTextShortcutsFromPastingPixels() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let image = Memory(body: "image notes", kind: .image)
        model.memories = [image]; model.select(image.id); model.shelfFocus = .cards
        let controller = ShelfController(model: model)
        var pasted = 0
        model.onPaste = { _ in pasted += 1 }
        func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        XCTAssertTrue(controller.handleKey(key(36, modifiers: .shift)))
        XCTAssertTrue(controller.handleKey(key(18, modifiers: [.command, .shift])))
        XCTAssertEqual(pasted, 0)
        XCTAssertNotNil(model.notice)
        XCTAssertTrue(controller.handleKey(key(36, modifiers: [])))
        XCTAssertTrue(controller.handleKey(key(18, modifiers: .command)))
        XCTAssertEqual(pasted, 2)
    }

    func testCustomKeysReplaceDefaultsAndRecordingNeverRunsCommands() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let records = [Memory(body: "first"), Memory(body: "second")]
        model.memories = records; model.select(records[0].id); model.shelfFocus = .cards
        model.preferences.shortcuts[.edit] = .init(40, "K", modifiers: KeyChord.command)
        model.preferences.shortcuts[.enterResults] = .init(126, "↑")
        model.preferences.shortcuts[.paste] = .disabled
        let controller = ShelfController(model: model)
        func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        var edited: UUID?, pasted: UUID?, copied: UUID?
        model.onEdit = { edited = $0?.id }; model.onPaste = { pasted = $0.id }; model.onCopy = { copied = $0.id }
        XCTAssertFalse(controller.handleKey(key(14, .command)))
        XCTAssertTrue(controller.handleKey(key(40, .command)))
        XCTAssertEqual(edited, records[0].id)
        XCTAssertFalse(controller.handleKey(key(36)))
        XCTAssertTrue(controller.handleKey(key(19, .command)))
        XCTAssertEqual(pasted, records[1].id)
        XCTAssertTrue(controller.handleKey(key(8, .command)))
        XCTAssertEqual(copied, records[0].id)
        model.recordingShortcut = true; edited = nil
        XCTAssertFalse(controller.handleKey(key(40, .command))); XCTAssertNil(edited)
        model.recordingShortcut = false; model.shelfFocus = .search
        XCTAssertFalse(controller.handleKey(key(125)))
        XCTAssertTrue(controller.handleKey(key(126)))
        XCTAssertEqual(model.shelfFocus, .cards)
    }

    func testShelfCommandsWorkWithoutSwiftUISceneAndLeaveTextCursorKeysAlone() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let first = Memory(body: "第一条"), second = Memory(body: "第二条")
        model.memories = [first, second]; model.select(first.id)
        let controller = ShelfController(model: model)
        func key(_ code: UInt16, _ characters: String = "", command: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        XCTAssertFalse(controller.handleKey(key(124))) // Right must still move the search caret.
        XCTAssertTrue(controller.handleKey(key(125)))
        XCTAssertEqual(model.shelfFocus, .cards)
        XCTAssertEqual(model.selectionID, first.id)
        XCTAssertTrue(controller.handleKey(key(124)))
        XCTAssertEqual(model.selectionID, second.id)
        var edited: UUID?
        model.onEdit = { edited = $0?.id }
        XCTAssertTrue(controller.panel.performKeyEquivalent(with: key(14, "e", command: true)))
        XCTAssertEqual(edited, second.id)
        XCTAssertTrue(controller.handleKey(key(3, "f", command: true)))
        XCTAssertEqual(model.shelfFocus, .search)
        XCTAssertFalse(controller.handleKey(key(123)))
        XCTAssertFalse(controller.handleKey(key(8, "c", command: true))) // Preserve normal copy.
    }
}
