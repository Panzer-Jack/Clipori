import AppKit
import SwiftUI
import CliporiCore
import ApplicationServices

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var shelf: ShelfController!
    private var clipboard: ClipboardMonitor!
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var applicationKeys: Any?
    private var editors: [UUID: EditorWindowDelegate] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        do { model = try AppModel() } catch {
            let alert = NSAlert(); alert.messageText = L("Clipori 无法打开本地数据"); alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        installMainMenu()
        shelf = ShelfController(model: model); clipboard = ClipboardMonitor(model: model)
        model.onDismiss = { [weak self] in self?.shelf.hide() }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onEdit = { [weak self] record in self?.showEditor(record: record) }
        model.onSticky = { [weak self] record in self?.showEditor(record: record, sticky: true) }
        model.onPrepareHistoryClear = { [weak self] in
            guard let self else { return true }
            for editor in Array(self.editors.values) {
                if !(await editor.editor.flush()) { return false }
            }
            return true
        }
        model.onHistoryCleared = { [weak self] in
            guard let self else { return }
            for editor in Array(self.editors.values) {
                editor.editor.discardChanges(); editor.window.close()
            }
            self.editors.removeAll()
            self.previewWindow?.close(); self.previewWindow = nil
        }
        model.onPaste = { [weak self] record in Task { await self?.paste(record) } }
        model.onCopy = { [weak self] record in Task { if await self?.clipboard.copy(record) == true { self?.model.toast(L("已复制")) } } }
        model.onPreview = { [weak self] record in self?.showPreview(record) }
        model.onRename = { [weak self] record in self?.showEditor(record: record, focusTitle: true) }
        model.onValidateShortcuts = { [weak self] value in try self?.hotKey?.update(value[.activate]) }
        model.onPreferencesChanged = { [weak self] in
            self?.installMainMenu(); self?.settingsWindow?.title = L("Clipori 设置")
            self?.shelf.panel.title = L("Clipori 记忆栏")
            for editor in self?.editors.values ?? [:].values { editor.window.title = L("Clipori 备忘") }
        }
        model.onShortcutRecording = { [weak self] recording in
            guard let self else { return }
            self.model.recordingShortcut = recording
            do { try self.hotKey?.update(recording ? .disabled : self.model.preferences.shortcuts[.activate]) }
            catch { self.model.errorMessage = error.localizedDescription }
        }
        applicationKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.model.recordingShortcut else { return event }
            let action = self.model.preferences.shortcuts.action(code: event.keyCode, modifiers: KeyChord.modifiers(event.modifierFlags))
            if action == .activate { self.shelf.toggle(); return nil }
            if action == .quit { NSApp.terminate(nil); return nil }
            if action == .save, self.editors.values.contains(where: { $0.window === NSApp.keyWindow }) { self.saveActiveNote(); return nil }
            return event
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image
        statusItem.button?.toolTip = "Clipori"
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        do { hotKey = try GlobalHotKey { [weak self] in MainActor.assumeIsolated { self?.shelf.toggle() } } }
        catch { model.toast(error.localizedDescription) }
        Task {
            await model.start()
            installMainMenu()
            shelf.panel.title = L("Clipori 记忆栏")
            do { try hotKey?.update(model.preferences.shortcuts[.activate]) } catch { model.toast(error.localizedDescription) }
            if !model.demo { clipboard.start() }
            shelf.show()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shelf?.show()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let pending = Array(editors.values)
        if pending.isEmpty { return .terminateNow }
        Task {
            for editor in pending {
                if !(await editor.editor.flush()) { editor.window.makeKeyAndOrderFront(nil); NSApp.reply(toApplicationShouldTerminate: false); return }
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: LF("打开 Clipori  %@", model.preferences.shortcuts[.activate].display), action: #selector(toggleShelf), keyEquivalent: "")
            menu.addItem(withTitle: model.preferences.capturePaused ? L("继续记录") : L("暂停记录"), action: #selector(toggleCapture), keyEquivalent: "")
            let settings = menu.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: "")
            model.preferences.shortcuts[.settings].apply(to: settings)
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: L("退出 Clipori"), action: #selector(quit), keyEquivalent: "")
            model.preferences.shortcuts[.quit].apply(to: quit)
            for item in menu.items { item.target = self }
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { shelf.toggle() }
    }
    @objc private func toggleShelf() { shelf.toggle() }
    @objc private func toggleCapture() {
        var prefs = model.preferences; prefs.capturePaused.toggle()
        Task { do { try await model.updatePreferences(prefs) } catch { model.errorMessage = error.localizedDescription } }
    }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func saveActiveNote() {
        if let active = editors.values.first(where: { $0.window === NSApp.keyWindow }) { Task { await active.editor.flush() } }
    }
    private func showSettings() {
        shelf.hide(restoreFocus: false)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("Clipori 设置"); window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false; window.center(); settingsWindow = window
        }
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(app: model))
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func showPreview(_ record: Memory) {
        shelf.hide(restoreFocus: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: record.kind == .image ? 820 : 540, height: record.kind == .image ? 580 : 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = record.displayTitle; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MemoryPreview(record: record, store: model.store))
        previewWindow?.close(); previewWindow = window
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    private func showEditor(record: Memory?, sticky: Bool = false, focusTitle: Bool = false) {
        guard !model.isClearingHistory else { return }
        shelf.hide(restoreFocus: false)
        let editor = EditorModel(record: record, app: model)
        let id = editor.id
        if let existing = editors[id] { NSApp.activate(ignoringOtherApps: true); existing.window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sticky ? 360 : 590, height: sticky ? 400 : 510), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = sticky ? L("Clipori 便笺") : L("Clipori 备忘"); window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 330, height: 300); window.isReleasedWhenClosed = false
        if sticky { window.level = .floating; window.setFrameAutosaveName("sticky-\(id.uuidString)") }
        window.contentView = NSHostingView(rootView: EditorView(editor: editor, app: model, sticky: sticky, focusTitle: focusTitle, onPin: { [weak window] pinned in window?.level = pinned ? .floating : .normal }))
        let delegate = EditorWindowDelegate(window: window, editor: editor) { [weak self] in self?.editors.removeValue(forKey: id) }
        window.delegate = delegate; editors[id] = delegate
        if !sticky || !window.setFrameUsingName("sticky-\(id.uuidString)") { window.center() }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    private func paste(_ record: Memory) async {
        let destination = shelf.previousApplication
        guard await clipboard.copy(record) else { return }
        guard let target = destination, !target.isTerminated else { model.toast(L("已复制，按 ⌘V 粘贴")); return }
        guard AXIsProcessTrusted() else {
            model.toast(L("已复制，按 ⌘V 粘贴 · 可在设置中授权直接粘贴"))
            return
        }
        shelf.hide()
        target.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { self?.model.toast(L("已复制，切换到目标应用后按 ⌘V")); return }
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let quitItem = appMenu.addItem(withTitle: L("退出 Clipori"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        model.preferences.shortcuts[.quit].apply(to: quitItem)
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); editItem.title = L("编辑"); let editMenu = NSMenu(title: L("编辑"))
        for (title, selector, key) in [(L("撤销"), "undo:", "z"), (L("剪切"), "cut:", "x"), (L("复制"), "copy:", "c"), (L("粘贴"), "paste:", "v"), (L("全选"), "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let save = editMenu.addItem(withTitle: L("保存备忘"), action: #selector(saveActiveNote), keyEquivalent: "s")
        save.target = self
        model.preferences.shortcuts[.save].apply(to: save)
        editItem.submenu = editMenu; main.addItem(editItem); NSApp.mainMenu = main
    }
}

@MainActor
final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    let window: NSWindow
    let editor: EditorModel
    private let onClose: () -> Void
    private var closing = false
    init(window: NSWindow, editor: EditorModel, onClose: @escaping () -> Void) { self.window = window; self.editor = editor; self.onClose = onClose }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing { return true }
        Task {
            guard await editor.flush() else { return }
            closing = true; sender.close(); onClose()
        }
        return false
    }
}
