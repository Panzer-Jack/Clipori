import AppKit
import SwiftUI

/// Native mouse events select immediately without waiting for a double-click gesture to fail.
struct CardPointerInput: NSViewRepresentable {
    var onSelect: (NSEvent.ModifierFlags) -> Void
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onActivate: () -> Void
    var onHoverChange: (Bool) -> Void
    var onBeginDrag: () -> MemoryDrag?
    var onEndDrag: () -> Void

    func makeNSView(context: Context) -> CardPointerView {
        let view = CardPointerView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: CardPointerView, context: Context) {
        view.onSelect = onSelect
        view.onClick = onClick
        view.onActivate = onActivate
        view.onHoverChange = onHoverChange
        view.onBeginDrag = onBeginDrag
        view.onEndDrag = onEndDrag
    }

    static func dismantleNSView(_ view: CardPointerView, coordinator: ()) {
        view.onSelect = nil
        view.onClick = nil
        view.onActivate = nil
        view.onHoverChange = nil
        view.onBeginDrag = nil
        view.onEndDrag = nil
    }
}

final class CardPointerView: NSView, NSDraggingSource {
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onActivate: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onBeginDrag: (() -> MemoryDrag?)?
    var onEndDrag: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private weak var observedClipView: NSClipView?
    private var scrollObserver: NSObjectProtocol?
    private var pointerInside = false
    private var pressLocation: NSPoint?
    private var dragged = false
    private var pressModifiers: NSEvent.ModifierFlags = []
    private var draggingSession: NSDraggingSession?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // On macOS 14+, an unclipped view's visibleRect can extend beyond its bounds.
        // Keep tracking local to this card instead of the whole scroll viewport.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        observeScrollView()
        // The shelf may appear or scroll beneath a stationary pointer. Refresh after layout,
        // rather than modifying SwiftUI state synchronously during its view update.
        DispatchQueue.main.async { [weak self] in self?.refreshHover() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrollView()
        DispatchQueue.main.async { [weak self] in self?.refreshHover() }
    }

    private func observeScrollView() {
        let clipView = window == nil ? nil : enclosingScrollView?.contentView
        guard clipView !== observedClipView else { return }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        observedClipView = clipView
        guard let clipView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHover() }
        }
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func refreshHover() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else {
            setHovered(false)
            return
        }
        let inside = bounds.intersection(visibleRect).contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        // Reaffirm the current owner after scrolling, even if an enter event was missed.
        setHovered(inside, reaffirm: inside)
    }

    private func setHovered(_ value: Bool, reaffirm: Bool = false) {
        guard reaffirm || value != pointerInside else { return }
        pointerInside = value
        onHoverChange?(value)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let SwiftUI handle context menus and the scroll view handle trackpad gestures.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || event.type == .rightMouseUp ||
           event.type == .scrollWheel || event.modifierFlags.contains(.control) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        pressModifiers = event.modifierFlags
        dragged = false
        onSelect?(pressModifiers)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressLocation, !dragged else { return }
        if hypot(event.locationInWindow.x - pressLocation.x, event.locationInWindow.y - pressLocation.y) > 4 {
            dragged = true
            guard window != nil, let drag = onBeginDrag?() else { return }
            setHovered(false)
            let item = NSDraggingItem(pasteboardWriter: drag.pasteboardItem)
            let point = convert(event.locationInWindow, from: nil)
            let preview = drag.preview()
            item.setDraggingFrame(NSRect(x: point.x - 30, y: point.y - 65, width: preview.size.width, height: preview.size.height), contents: preview)
            draggingSession = beginDraggingSession(with: [item], event: event, source: self)
            draggingSession?.animatesToStartingPositionsOnCancelOrFail = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let clicked = pressLocation != nil && !dragged && bounds.contains(convert(event.locationInWindow, from: nil))
        let shouldActivate = clicked && event.clickCount == 2 && pressModifiers.intersection([.command, .shift]).isEmpty
        pressLocation = nil
        // The second click pastes; do not also start a competing asynchronous image copy.
        if shouldActivate { onActivate?() }
        else if clicked { onClick?(pressModifiers) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingSession = nil; pressLocation = nil
        onEndDrag?()
        refreshHover()
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }
}
