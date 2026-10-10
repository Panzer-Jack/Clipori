import Foundation

public struct HistoryRetention: Identifiable, Sendable {
    public let days: Int
    public let titleKey: String
    public var id: Int { days }
    public var title: String { L(titleKey) }
    public static let presets: [Self] = [
        .init(days: 1, titleKey: "1 天"), .init(days: 7, titleKey: "1 周"),
        .init(days: 30, titleKey: "1 个月 · 默认"), .init(days: 365, titleKey: "1 年"), .init(days: 0, titleKey: "永久")
    ]
}
