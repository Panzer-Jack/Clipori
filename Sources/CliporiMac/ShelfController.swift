import AppKit
import SwiftUI
import Combine
import CliporiCore
import QuartzCore

final class ShelfPanel: NSPanel {
    var commandHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        commandHandler?(event) == true || super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class ShelfController: NSObject, NSWindowDelegate {
    private let model: AppModel
    let panel: ShelfPanel
    private var displayLink: CADisplayLink?
    private var targetVisible = false
    private var destination = NSRect.zero
    private var position = ShelfSpring(value: 0)
    private var opacity = ShelfSpring(value: 0)
    private var height = ShelfSpring(value: 420)
    private var previousTick = 0.0
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var answerSubscription: AnyCancellable?
    var previousApplication: NSRunningApplication?

    init(model: AppModel) {
        self.model = model
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 420), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.title = L("Clipori 记忆栏")
        panel.setAccessibilityRole(.window); panel.setAccessibilitySubrole(.floatingWindow)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = false; panel.animationBehavior = .none
        panel.delegate = self; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShelfView(model: model))
        panel.commandHandler = { [weak self] event in self?.handleKey(event) ?? false }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.targetVisible, event.window === self.panel || NSApp.keyWindow === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        answerSubscription = model.$aiAnswer.map { !$0.isEmpty }.removeDuplicates().sink { [weak self] hasAnswer in
            DispatchQueue.main.async { self?.resize(hasAnswer: hasAnswer) }
        }
    }
    func toggle() { targetVisible ? hide() : show() }
    func show() {
        let opening = !targetVisible
        if !targetVisible {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = front }
        }
        targetVisible = true; model.isVisible = true; model.shelfFocus = .search; model.presentation = UUID()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        // Include the transparent hosting-view padding so all three visible edges match.
        let edgeInset: CGFloat = 32
        let windowInset = edgeInset - ShelfView.windowPadding
        let width = visible.width - windowInset * 2
        // Anchor to the physical screen bottom; visibleFrame also includes the Dock's reserved height.
        destination = NSRect(x: visible.minX + windowInset, y: screen.frame.minY + windowInset,
                             width: width, height: model.aiAnswer.isEmpty ? 420 : 484)
        if !panel.isVisible {
            position = ShelfSpring(value: destination.minY - 64)
            opacity = ShelfSpring(value: 0)
            height = ShelfSpring(value: destination.height)
            panel.setFrame(NSRect(x: destination.minX, y: position.value, width: width, height: destination.height), display: false)
            panel.alphaValue = 0
        }
        // Keep command-key routing on the shelf even when another Clipori window is open.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.hide(restoreFocus: false) }
            }
        }
        animate()
        if opening { Task { await model.refreshForPresentation() } }
    }
    func hide(restoreFocus: Bool = true) {
        guard targetVisible else { return }
        targetVisible = false; model.isVisible = false
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        panel.resignKey()
        if restoreFocus { previousApplication?.activate(options: []) }
        animate()
    }
    private func resize(hasAnswer: Bool) {
        guard targetVisible else { return }
        destination.size.height = hasAnswer ? 484 : 420
        animate()
    }
    /// NSHostingView inside an accessory NSPanel has no SwiftUI scene shortcut dispatcher.
    /// Route keys before the field editor, while leaving marked IME text and cursor movement alone.
    func handleKey(_ event: NSEvent) -> Bool {
        guard !model.recordingShortcut else { return false }
        let modifiers = KeyChord.modifiers(event.modifierFlags)
        if let input = panel.firstResponder as? NSTextInputClient, input.hasMarkedText(), modifiers == 0 { return false }
        guard let action = model.preferences.shortcuts.action(code: event.keyCode, modifiers: modifiers), action != .activate else { return false }
        if model.shelfFocus == .search {
            let typing: Set<ShortcutAction> = [.previous, .next, .delete, .preview, .copy, .undo]
            if typing.contains(action) { return false }
            if modifiers & (KeyChord.command | KeyChord.control | KeyChord.option) == 0 && ![.dismiss, .paste, .pastePlain, .switchFocus, .enterResults].contains(action) { return false }
        }
        if let index = action.quickIndex {
            if model.displayed.indices.contains(index) { model.paste(model.displayed[index], plainText: action.rawValue.hasPrefix("plain")) }
            return true
        }
        switch action {
        case .dismiss: hide()
        case .enterResults:
            model.shelfFocus = .cards
            if model.selectionID == nil { model.select(model.displayed.first?.id) }
        case .previous: model.moveSelection(-1)
        case .next: model.moveSelection(1)
        case .first: model.shelfFocus = .cards; model.select(model.displayed.first?.id)
        case .last: model.shelfFocus = .cards; model.select(model.displayed.last?.id)
        case .paste, .pastePlain: model.pasteSelected(plainText: action == .pastePlain)
        case .copy: if let record = model.selected { model.onCopy?(record) }
        case .preview: if let record = model.selected { model.onPreview?(record) }
        case .open:
            if let record = model.selected,
               let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
               let url = detector.firstMatch(in: record.body, range: NSRange(record.body.startIndex..., in: record.body))?.url,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); hide() }
        case .rename: if let record = model.selected { model.onRename?(record) }
        case .edit: model.editSelected()
        case .newMemory: model.onEdit?(nil)
        case .delete: if let record = model.selected { model.delete(record) }
        case .undo: model.undoDeletion()
        case .search: model.shelfFocus = .search; model.presentation = UUID()
        case .switchFocus: model.shelfFocus = model.shelfFocus == .search ? .cards : .search
        case .previousCategory: model.moveCategory(-1)
        case .nextCategory: model.moveCategory(1)
        case .newPinboard: model.requestedSettingsTab = 2; model.requestNewPinboard = true; model.onSettings?()
        case .pause: model.toggleCapture()
        case .settings: model.onSettings?()
        case .quit: NSApp.terminate(nil)
        case .pin: if let record = model.selected { model.toggleProtected(record) }
        case .aiSearch: model.runAISearch()
        default: return false
        }
        return true
    }
    /// Retarget the same spring, keeping current position and velocity during rapid reversals.
    private func animate() {
        guard model.motion else {
            finishAnimation()
            return
        }
        guard displayLink == nil else { return }
        previousTick = CACurrentMediaTime()
        let link = panel.displayLink(target: self, selector: #selector(tick(_:)))
        let fps = Float(panel.screen?.maximumFramesPerSecond ?? 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = max(0, now - previousTick); previousTick = now
        let target = targetVisible ? destination.minY : destination.minY - 24
        let alphaTarget = targetVisible ? 1.0 : 0.0
        position.advance(to: target, response: targetVisible ? 0.30 : 0.22, damping: targetVisible ? 0.58 : 1, by: dt)
        opacity.advance(to: alphaTarget, response: targetVisible ? 0.18 : 0.14, damping: 1, by: dt)
        height.advance(to: destination.height, response: 0.30, damping: 0.86, by: dt)
        // Let AppKit composite on the display's next frame instead of forcing a synchronous redraw.
        panel.setFrame(NSRect(x: destination.minX, y: position.value, width: destination.width, height: height.value), display: false)
        panel.alphaValue = min(1, max(0, opacity.value))
        if (!targetVisible && opacity.value < 0.01) ||
            (position.isSettled(at: target) && height.isSettled(at: destination.height) && opacity.isSettled(at: alphaTarget, distance: 0.004, speed: 0.1)) {
            finishAnimation()
        }
    }

    private func finishAnimation() {
        displayLink?.invalidate(); displayLink = nil
        position = ShelfSpring(value: destination.minY)
        opacity = ShelfSpring(value: targetVisible ? 1 : 0)
        height = ShelfSpring(value: destination.height)
        panel.alphaValue = opacity.value
        panel.setFrame(destination, display: false)
        if !targetVisible { panel.orderOut(nil) }
    }
}
