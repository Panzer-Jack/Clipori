import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, chinese, english
    public var title: String { switch self { case .system: return L("跟随系统"); case .chinese: return "简体中文"; case .english: return "English" } }
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
}
public enum L10n {
    private static let lock = NSLock()
    private static var selection = AppLanguage.system
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selection }
        set { lock.lock(); selection = newValue; lock.unlock() }
    }
    public static var locale: Locale { Locale(identifier: language.resolved() == .chinese ? "zh-Hans" : "en") }
    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        (language ?? self.language).resolved() == .chinese ? key : (Translations.english[key] ?? key)
    }
}
public func L(_ key: String) -> String { L10n.text(key) }
public func LF(_ key: String, _ arguments: CVarArg...) -> String { String(format: L(key), locale: L10n.locale, arguments: arguments) }
