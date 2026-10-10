import Foundation

public struct KeyChord: Codable, Equatable, Hashable, Sendable {
    public static let command: UInt = 1, shift: UInt = 2, option: UInt = 4, control: UInt = 8
    public var keyCode: UInt16
    public var modifiers: UInt
    public var keyName: String
    public init(_ code: UInt16, _ name: String, modifiers: UInt = 0) { keyCode = code; keyName = name; self.modifiers = modifiers }
    public static let disabled = KeyChord(UInt16.max, "")
    public var enabled: Bool { keyCode != UInt16.max }
    public var display: String {
        guard enabled else { return L("未设置") }
        return (modifiers & Self.control != 0 ? "⌃" : "") + (modifiers & Self.option != 0 ? "⌥" : "") + (modifiers & Self.shift != 0 ? "⇧" : "") + (modifiers & Self.command != 0 ? "⌘" : "") + keyName
    }
    public func matches(code: UInt16, modifiers: UInt) -> Bool { enabled && keyCode == code && self.modifiers == modifiers }
}

public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case activate, dismiss, enterResults, previous, next, first, last, paste, pastePlain, copy, preview, open, rename, edit, newMemory, delete, undo, search, switchFocus, previousCategory, nextCategory, newPinboard, pause, settings, quit, save, pin, aiSearch
    case quick1, quick2, quick3, quick4, quick5, quick6, quick7, quick8, quick9
    case plain1, plain2, plain3, plain4, plain5, plain6, plain7, plain8, plain9

    public var quickIndex: Int? {
        if rawValue.hasPrefix("quick") { return Int(rawValue.dropFirst(5)).map { $0 - 1 } }
        if rawValue.hasPrefix("plain") { return Int(rawValue.dropFirst(5)).map { $0 - 1 } }
        return nil
    }
    public var title: String {
        if self == .enterResults { return L("进入卡片选择") }
        if let index = quickIndex { return LF(rawValue.hasPrefix("plain") ? "纯文本快贴 %d" : "快速粘贴 %d", index + 1) }
        let names: [Self: String] = [.activate:"显示 / 收起卡片栏", .dismiss:"收起卡片栏", .previous:"上一条记录", .next:"下一条记录", .first:"第一条记录", .last:"最后一条记录", .paste:"粘贴所选内容", .pastePlain:"粘贴为纯文本", .copy:"复制所选内容", .preview:"预览记录", .open:"打开链接", .rename:"重命名记录", .edit:"编辑记录", .newMemory:"新建备忘", .delete:"删除记录", .undo:"撤销删除", .search:"搜索", .switchFocus:"切换搜索与卡片", .previousCategory:"上一个分类", .nextCategory:"下一个分类", .newPinboard:"新建固定分类", .pause:"暂停 / 继续记录", .settings:"设置", .quit:"退出 Clipori", .save:"保存备忘", .pin:"固定 / 取消固定", .aiSearch:"AI 找回"]
        return L(names[self] ?? rawValue)
    }
    public var defaultChord: KeyChord {
        let c = KeyChord.command, s = KeyChord.shift
        if let index = quickIndex {
            let codes: [UInt16] = [18,19,20,21,23,22,26,28,25]
            return .init(codes[index], String(index + 1), modifiers: c | (rawValue.hasPrefix("plain") ? s : 0))
        }
        switch self {
        case .activate: return .init(9, "V", modifiers: c | s)
        case .dismiss: return .init(53, "Esc")
        case .enterResults: return .init(125, "↓")
        case .previous: return .init(123, "←")
        case .next: return .init(124, "→")
        case .first: return .init(126, "↑", modifiers: c)
        case .last: return .init(125, "↓", modifiers: c)
        case .paste: return .init(36, "↩")
        case .pastePlain: return .init(36, "↩", modifiers: s)
        case .copy: return .init(8, "C", modifiers: c)
        case .preview: return .init(49, "Space")
        case .open: return .init(31, "O", modifiers: c)
        case .rename: return .init(15, "R", modifiers: c)
        case .edit: return .init(14, "E", modifiers: c)
        case .newMemory: return .init(45, "N", modifiers: c)
        case .delete: return .init(51, "⌫")
        case .undo: return .init(6, "Z", modifiers: c)
        case .search: return .init(3, "F", modifiers: c)
        case .switchFocus: return .init(48, "⇥")
        case .previousCategory: return .init(123, "←", modifiers: c)
        case .nextCategory: return .init(124, "→", modifiers: c)
        case .newPinboard: return .init(45, "N", modifiers: c | s)
        case .pause: return .init(17, "T", modifiers: c)
        case .settings: return .init(43, ",", modifiers: c)
        case .quit: return .init(12, "Q", modifiers: c)
        case .save: return .init(1, "S", modifiers: c)
        case .pin: return .init(35, "P", modifiers: c | s)
        case .aiSearch: return .init(36, "↩", modifiers: c)
        default: return .disabled
        }
    }
}

public struct ShortcutPreferences: Codable, Equatable, Sendable {
    public var overrides: [String: KeyChord] = [:]
    public init() {}
    public subscript(_ action: ShortcutAction) -> KeyChord {
        get { overrides[action.rawValue] ?? action.defaultChord }
        set { overrides[action.rawValue] = newValue }
    }
    public func action(code: UInt16, modifiers: UInt) -> ShortcutAction? {
        ShortcutAction.allCases.first { self[$0].matches(code: code, modifiers: modifiers) }
    }
    public func validate() throws {
        for (offset, action) in ShortcutAction.allCases.enumerated() {
            let chord = self[action]; guard chord.enabled else { continue }
            if [.activate, .save, .quit].contains(action) && chord.modifiers & (KeyChord.command | KeyChord.control | KeyChord.option) == 0 {
                throw ShortcutError(message: LF("%@ 需要包含 ⌘、⌃ 或 ⌥，避免影响正常输入。", action.title))
            }
            if let other = ShortcutAction.allCases.dropFirst(offset + 1).first(where: { self[$0].matches(code: chord.keyCode, modifiers: chord.modifiers) }) {
                throw ShortcutError(message: LF("%@ 与 %@ 使用了相同的快捷键 %@。", action.title, other.title, chord.display))
            }
        }
    }
}
public struct ShortcutError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
