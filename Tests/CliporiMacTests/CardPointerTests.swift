import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class CardPointerTests: XCTestCase {
    func testHoverEntersAndLeavesWithoutSelectingOrPasting() {
        _ = NSApplication.shared
        let view = CardPointerView(frame: NSRect(x: 0, y: 0, width: 237, height: 233))
        var hoverChanges: [Bool] = []
        var selections = 0, activations = 0, clicks = 0
        view.onHoverChange = { hoverChanges.append($0) }
        view.onSelect = { _ in selections += 1 }
        view.onActivate = { activations += 1 }
        view.onClick = { _ in clicks += 1 }
        let event = NSEvent.enterExitEvent(with: .mouseEntered, location: NSPoint(x: 20, y: 20),
                                         modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
                                         eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseEntered(with: event)
        view.mouseEntered(with: event)
        XCTAssertEqual(hoverChanges, [true])
        view.mouseExited(with: event)
        XCTAssertEqual(hoverChanges, [true, false])
        XCTAssertEqual(selections, 0)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(clicks, 0)
    }

    func testTrackingSurvivesLayoutUpdatesWithoutMovingTheClickRegion() throws {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 237, height: 233)
        let view = CardPointerView(frame: frame)
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        XCTAssertEqual(view.trackingAreas.count, 1)
        let area = try XCTUnwrap(view.trackingAreas.first)
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertFalse(area.options.contains(.inVisibleRect))
        XCTAssertEqual(area.rect, view.bounds)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertEqual(view.frame, frame)
    }

    func testScrollingUnderStationaryPointerTransfersHoverWithoutExitEvents() {
        _ = NSApplication.shared
        let window = PointerTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 233),
                                       styleMask: .borderless, backing: .buffered, defer: false)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 233))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 233))
        let first = CardPointerView(frame: NSRect(x: 0, y: 0, width: 237, height: 233))
        let second = CardPointerView(frame: NSRect(x: 251, y: 0, width: 237, height: 233))
        document.addSubview(first)
        document.addSubview(second)
        scrollView.documentView = document
        window.contentView = scrollView
        var hovered: Set<Int> = []
        first.onHoverChange = { if $0 { hovered.insert(1) } else { hovered.remove(1) } }
        second.onHoverChange = { if $0 { hovered.insert(2) } else { hovered.remove(2) } }
        first.updateTrackingAreas()
        second.updateTrackingAreas()

        // Only the content moves. No mouseEntered/mouseExited events are sent.
        scrollView.contentView.scroll(to: NSPoint(x: 1, y: 0))
        XCTAssertEqual(hovered, [1])
        scrollView.contentView.scroll(to: NSPoint(x: 251, y: 0))
        XCTAssertEqual(hovered, [2])
        scrollView.contentView.scroll(to: NSPoint(x: 220, y: 0))
        XCTAssertTrue(hovered.isEmpty, "The space between cards must clear hover")
        scrollView.contentView.scroll(to: .zero)
        XCTAssertEqual(hovered, [1])
    }

    func testPressSelectsImmediatelyAndOnlyDoubleClickActivates() {
        _ = NSApplication.shared
        let view = CardPointerView(frame: NSRect(x: 0, y: 0, width: 237, height: 233))
        var selected = 0, activated = 0, clicked = 0
        view.onSelect = { _ in selected += 1 }
        view.onActivate = { activated += 1 }
        view.onClick = { _ in clicked += 1 }

        view.mouseDown(with: mouse(.leftMouseDown, count: 1))
        // No mouse-up, timer, or second click is needed to show selection.
        XCTAssertEqual(selected, 1)
        XCTAssertEqual(activated, 0)
        XCTAssertEqual(clicked, 0)
        view.mouseUp(with: mouse(.leftMouseUp, count: 1))
        XCTAssertEqual(activated, 0)
        XCTAssertEqual(clicked, 1, "Single-click copy must not wait for double-click detection")

        view.mouseDown(with: mouse(.leftMouseDown, count: 2))
        view.mouseUp(with: mouse(.leftMouseUp, count: 2))
        XCTAssertEqual(selected, 2)
        XCTAssertEqual(activated, 1)
        XCTAssertEqual(clicked, 1, "Double-click must not start both a copy and a paste")
        view.mouseDown(with: mouse(.leftMouseDown, count: 3))
        view.mouseUp(with: mouse(.leftMouseUp, count: 3))
        XCTAssertEqual(activated, 1)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testDraggingOrReleasingOutsideDoesNotCopyOrPaste() {
        _ = NSApplication.shared
        let view = CardPointerView(frame: NSRect(x: 0, y: 0, width: 237, height: 233))
        var activated = 0, clicked = 0
        view.onActivate = { activated += 1 }
        view.onClick = { _ in clicked += 1 }
        view.mouseUp(with: mouse(.leftMouseUp, count: 2))
        view.mouseDown(with: mouse(.leftMouseDown, count: 2))
        view.mouseDragged(with: mouse(.leftMouseDragged, count: 2, point: NSPoint(x: 80, y: 20)))
        view.mouseUp(with: mouse(.leftMouseUp, count: 2))
        XCTAssertEqual(activated, 0)
        view.mouseDown(with: mouse(.leftMouseDown, count: 2))
        view.mouseUp(with: mouse(.leftMouseUp, count: 2, point: NSPoint(x: 280, y: 20)))
        XCTAssertEqual(activated, 0)
        XCTAssertEqual(clicked, 0)
    }

    func testModifiedClicksSelectWithoutDoubleClickPastingOrLosingTheirModifiers() {
        _ = NSApplication.shared
        let view = CardPointerView(frame: NSRect(x: 0, y: 0, width: 237, height: 233))
        var presses: [NSEvent.ModifierFlags] = [], clicks: [NSEvent.ModifierFlags] = []
        var activated = 0
        view.onSelect = { presses.append($0) }
        view.onClick = { clicks.append($0) }
        view.onActivate = { activated += 1 }
        for modifiers: NSEvent.ModifierFlags in [.command, .shift] {
            view.mouseDown(with: mouse(.leftMouseDown, count: 2, modifiers: modifiers))
            // Releasing the modifier key before the mouse must not collapse the group.
            view.mouseUp(with: mouse(.leftMouseUp, count: 2))
        }
        XCTAssertEqual(presses, [.command, .shift])
        XCTAssertEqual(clicks, presses)
        XCTAssertEqual(activated, 0)
        view.mouseDown(with: mouse(.leftMouseDown, count: 1))
        view.mouseDragged(with: mouse(.leftMouseDragged, count: 1, point: NSPoint(x: 60, y: 20)))
        view.mouseUp(with: mouse(.leftMouseUp, count: 1))
        XCTAssertEqual(clicks.count, 2, "Dragging must not emit a plain click that collapses selection")
    }

    func testPointerSelectionStaysStillAndKeyboardSelectionRequestsScrolling() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let records = [Memory(body: "first"), Memory(body: "second"), Memory(body: "third")]
        model.memories = records
        model.select(records[0].id)
        XCTAssertEqual(model.selectionToReveal, records[0].id)
        model.select(records[1].id, reveal: false)
        XCTAssertEqual(model.selected?.id, records[1].id)
        XCTAssertNil(model.selectionToReveal)
        model.moveSelection(1)
        XCTAssertEqual(model.selected?.id, records[2].id)
        XCTAssertEqual(model.selectionToReveal, records[2].id)
    }

    private func mouse(_ type: NSEvent.EventType, count: Int, point: NSPoint = NSPoint(x: 20, y: 20), modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 1,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
    }
}

@MainActor
private final class PointerTestWindow: NSWindow {
    override var isVisible: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { NSPoint(x: 20, y: 20) }
}
