import SwiftUI
import CliporiCore

struct ShortcutSettingsView: View {
    @Binding var shortcuts: ShortcutPreferences
    let recording: (Bool) -> Void
    @State private var feedback = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("快捷键")).font(.headline)
                Spacer()
                Button(L("恢复全部默认")) { shortcuts = ShortcutPreferences(); feedback = "" }
            }
            Text(L("点击键位后按下新的组合。Esc 取消录制，× 清除。修改后保存设置。")).font(.caption).foregroundStyle(.secondary)
            if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(.orange) }
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title).font(.system(size: 12))
                    Spacer()
                    ShortcutRecorder(chord: shortcuts[action], recording: recording) { chord in
                        var next = shortcuts; next[action] = chord
                        do { try next.validate(); shortcuts = next; feedback = "" }
                        catch { feedback = error.localizedDescription }
                    }.frame(width: 125, height: 26)
                    Button { shortcuts[action] = .disabled } label: { Image(systemName: "xmark.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L("清除此快捷键"))
                }
                if [.activate, .last, .aiSearch, .quick9].contains(action) { Divider() }
            }
            Text(L("无修饰键的操作仅在卡片区域生效，避免影响文字输入。全局呼出需要包含 ⌘、⌃ 或 ⌥。")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let chord: KeyChord
    let recording: (Bool) -> Void
    let capture: (KeyChord) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(); button.bezelStyle = .rounded
        button.target = button; button.action = #selector(RecorderButton.begin)
        button.recording = recording; button.capture = capture; button.title = chord.display
        return button
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.recording = recording; view.capture = capture; view.display = chord.display
        if !view.isRecording { view.title = chord.display }
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.finish() }
}

private final class RecorderButton: NSButton {
    var recording: (Bool) -> Void = { _ in }
    var capture: (KeyChord) -> Void = { _ in }
    var display = ""
    private(set) var isRecording = false
    private var monitor: Any?
    @objc func begin() {
        guard !isRecording else { finish(); return }
        isRecording = true; title = L("请按快捷键…"); recording(true)
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            let chord = KeyChord(event: event)
            self.finish()
            if !(event.keyCode == 53 && chord.modifiers == 0) { self.capture(chord) }
            return nil
        }
    }
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    func finish() {
        guard isRecording else { return }
        isRecording = false; title = display
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording(false)
    }
}
