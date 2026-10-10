import AppKit
import CliporiCore

extension KeyChord {
    init(event: NSEvent) {
        let names: [UInt16: String] = [36:"↩", 76:"⌤", 48:"⇥", 49:"Space", 51:"⌫", 53:"Esc", 117:"⌦", 123:"←", 124:"→", 125:"↓", 126:"↑"]
        let functions: [UInt16: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
        self.init(event.keyCode, names[event.keyCode] ?? functions[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?", modifiers: Self.modifiers(event.modifierFlags))
    }
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> UInt {
        (flags.contains(.command) ? command : 0) | (flags.contains(.shift) ? shift : 0) | (flags.contains(.option) ? option : 0) | (flags.contains(.control) ? control : 0)
    }
    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & Self.command != 0 { flags.insert(.command) }
        if modifiers & Self.shift != 0 { flags.insert(.shift) }
        if modifiers & Self.option != 0 { flags.insert(.option) }
        if modifiers & Self.control != 0 { flags.insert(.control) }
        return flags
    }
    func apply(to item: NSMenuItem) {
        item.keyEquivalent = enabled ? (keyName.count == 1 ? keyName.lowercased() : "") : ""
        item.keyEquivalentModifierMask = eventModifiers
    }
}
