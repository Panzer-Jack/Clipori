import AppKit
import Carbon
import CliporiCore

final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var chord = KeyChord.disabled
    private let action: () -> Void
    init(action: @escaping () -> Void) throws {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(data).takeUnretainedValue().action()
            return noErr
        }, 1, &type, context, &handler)
        if result != noErr { throw ShortcutError(message: L("无法安装全局快捷键监听，可继续使用菜单栏入口。")) }
    }
    func update(_ value: KeyChord) throws {
        guard value != chord else { return }
        if chord.matches(code: value.keyCode, modifiers: value.modifiers) { chord = value; return }
        if !value.enabled {
            if let reference { UnregisterEventHotKey(reference) }; reference = nil; chord = value; return
        }
        var flags: UInt32 = 0
        if value.modifiers & KeyChord.command != 0 { flags |= UInt32(cmdKey) }
        if value.modifiers & KeyChord.shift != 0 { flags |= UInt32(shiftKey) }
        if value.modifiers & KeyChord.option != 0 { flags |= UInt32(optionKey) }
        if value.modifiers & KeyChord.control != 0 { flags |= UInt32(controlKey) }
        var next: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(value.keyCode), flags, EventHotKeyID(signature: 0x434C4950, id: 1), GetApplicationEventTarget(), 0, &next)
        guard result == noErr else { throw ShortcutError(message: LF("快捷键 %@ 被其他应用占用，请选择其他组合。", value.display)) }
        if let reference { UnregisterEventHotKey(reference) }
        reference = next; chord = value
    }
    deinit { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
