import AppKit
import SwiftUI
import CliporiCore

/// Only an opaque session token goes on the dragging pasteboard; no clipboard content is exported.
struct MemoryDrag {
    static let pasteboardType = NSPasteboard.PasteboardType("app.clipori.memory-selection")
    let token = UUID()
    let ids: [UUID]
    let title: String

    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(token.uuidString, forType: Self.pasteboardType)
        return item
    }

    func preview() -> NSImage {
        let size = NSSize(width: 176, height: 90)
        return NSImage(size: size, flipped: false) { rect in
            if ids.count > 1 {
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: NSRect(x: 14, y: 4, width: 156, height: 70), xRadius: 12, yRadius: 12).fill()
            }
            NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
            let card = NSBezierPath(roundedRect: NSRect(x: 3, y: 12, width: 158, height: 70), xRadius: 12, yRadius: 12)
            card.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            card.lineWidth = 1.5; card.stroke()
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            (title as NSString).draw(in: NSRect(x: 14, y: 28, width: 136, height: 38), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: style
            ])
            let count = String(ids.count) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white]
            let textSize = count.size(withAttributes: attributes)
            let badge = NSRect(x: rect.maxX - max(24, textSize.width + 12), y: 65, width: max(24, textSize.width + 12), height: 24)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 12, yRadius: 12).fill()
            count.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2), withAttributes: attributes)
            return true
        }
    }
}

/// Keep both ends of the drag in AppKit: SwiftUI's item-provider bridge does not reliably
/// negotiate our private, move-only pasteboard type inside the nonactivating panel.
struct CategoryDropTarget: NSViewRepresentable {
    let categoryID: UUID?
    let model: AppModel
    let onClick: () -> Void
    let onTargetChange: (Bool) -> Void

    func makeNSView(context: Context) -> CategoryDropView {
        let view = CategoryDropView()
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: CategoryDropView, context: Context) {
        view.model = model; view.categoryID = categoryID
        view.onClick = onClick; view.onTargetChange = onTargetChange
    }
    static func dismantleNSView(_ view: CategoryDropView, coordinator: ()) {
        view.model = nil; view.onClick = nil; view.onTargetChange = nil
    }
}

final class CategoryDropView: NSView {
    weak var model: AppModel?
    var categoryID: UUID?
    var onClick: (() -> Void)?
    var onTargetChange: ((Bool) -> Void)?
    private var pressed = false
    private var targeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([MemoryDrag.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if NSApp.currentEvent?.type == .scrollWheel { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        if pressed && bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        pressed = false
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let model, let drag = model.memoryDrag, let categoryID,
              model.categories.contains(where: { $0.id == categoryID }) else { return false }
        return sender.draggingSource is CardPointerView && sender.draggingSourceOperationMask.contains(.move) &&
            sender.draggingPasteboard.string(forType: MemoryDrag.pasteboardType) == drag.token.uuidString
    }
    private func setTargeted(_ value: Bool) {
        guard targeted != value else { return }
        targeted = value; onTargetChange?(value)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = accepts(sender)
        setTargeted(accepted)
        return accepted ? .move : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { setTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { setTargeted(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setTargeted(false)
        guard accepts(sender), let categoryID else { return false }
        return model?.dropMemories(to: categoryID) == true
    }
}
