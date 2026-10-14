import AppKit
import SwiftUI
import CliporiCore

@MainActor
final class DailyNotesController: NSObject, NSWindowDelegate {
    let model: DailyNotesModel
    let assistant: DailyNoteAssistant
    let window: NSWindow
    private var timer: Timer?
    private var closing = false
    private var opening: Task<Void, Never>?

    init(app: AppModel) throws {
        model = DailyNotesModel(store: try DailyNoteStore(url: app.dataDirectory.appendingPathComponent("daily-notes.sqlite")))
        assistant = DailyNoteAssistant(store: app.store) { [weak app] context, note in
            guard let app, app.preferences.ai.isConfigured else { throw AIError.configuration(L("请先在设置中配置 AI 服务与模型。")) }
            return try await app.makeAIClient().suggestDailyNotes(context: context, existing: note)
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("每日备忘录"); window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 820, height: 460); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DailyNotesView(model: model, app: app, assistant: assistant))
        window.delegate = self; window.center()
        window.setFrameAutosaveName("daily-notes")
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDay() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(checkDay), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(checkDay), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func show(adding memory: Memory? = nil) {
        window.title = L("每日备忘录")
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        let previous = opening
        opening = Task { [self] in
            await previous?.value
            await model.refreshToday()
            if let memory, model.errorMessage == nil {
                await model.selectDay(model.today)
                guard model.note?.day == model.today, !model.isLoading else { return }
                model.addItem(title: memory.displayTitle, note: memory.body)
            }
        }
    }

    @objc private func checkDay() {
        guard model.note != nil, DailyNoteDay.key(for: Date()) != model.today else { return }
        Task { await model.refreshToday() }
    }

    func flush() async -> Bool {
        await opening?.value
        return await model.flush()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing else { return false }
        assistant.dismiss()
        closing = true
        Task {
            if await flush() { window.orderOut(nil) }
            closing = false
        }
        return false
    }
}
