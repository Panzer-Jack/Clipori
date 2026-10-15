import Foundation

public enum ContentKind: String, Codable, Sendable { case text, link, image }
public enum CategoryAssignment: String, Codable, Sendable { case none, automatic, manual }

public struct Memory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var kind: ContentKind
    public var source: String
    public var sourceBundleID: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var categoryID: UUID?
    public var assignment: CategoryAssignment
    public var keepForever: Bool
    public var attachment: String?
    public var imageSize: ImageSize?

    public struct ImageSize: Codable, Equatable, Sendable {
        public let width: Int
        public let height: Int
        public init(width: Int, height: Int) { self.width = width; self.height = height }
    }

    public init(id: UUID = UUID(), title: String = "", body: String, kind: ContentKind? = nil,
                source: String = "手动记录", sourceBundleID: String? = nil, now: Date = Date()) {
        self.id = id; self.title = title; self.body = body
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind ?? ((trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://")) && !trimmed.contains("\n") ? .link : .text)
        self.source = source; self.sourceBundleID = sourceBundleID
        createdAt = now; modifiedAt = now
        categoryID = nil; assignment = .none; keepForever = false; attachment = nil
    }

    public var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        let firstLine = body.prefix { !$0.isNewline }.prefix(70)
        return firstLine.isEmpty ? L(kind == .image ? "图片" : "新备忘") : String(firstLine)
    }
    /// User-perceived characters, including punctuation and emoji, excluding whitespace.
    public var characterCount: Int { body.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) } }
    public var canClassify: Bool {
        categoryID == nil && assignment != .manual &&
        (kind != .image || !(title + body).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    public var displaySource: String {
        for key in ["手动记录", "剪贴板", "iPhone 剪贴板"] where source == key || source == L10n.text(key, language: .english) { return L(key) }
        return source
    }
}

public struct MemoryCategory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: String
    public var modifiedAt: Date
    public var isPinboard: Bool
    public init(id: UUID = UUID(), name: String, color: String, modifiedAt: Date = Date(), isPinboard: Bool = false) {
        self.id = id; self.name = name; self.color = color; self.modifiedAt = modifiedAt; self.isPinboard = isPinboard
    }
    enum CodingKeys: String, CodingKey { case id, name, color, modifiedAt, isPinboard }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        color = try values.decode(String.self, forKey: .color); modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        isPinboard = try values.decodeIfPresent(Bool.self, forKey: .isPinboard) ?? false
    }
    public var displayName: String {
        let defaultNames = ["工作", "学习", "生活", "代码", "灵感"]
        if let index = Self.defaults.firstIndex(where: { $0.id == id }), name == defaultNames[index] || name == L10n.text(defaultNames[index], language: .english) { return L(defaultNames[index]) }
        return name
    }
    public static let defaults: [MemoryCategory] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "工作", color: "lavender", modifiedAt: Date(timeIntervalSince1970: 0)),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "学习", color: "blue", modifiedAt: Date(timeIntervalSince1970: 0)),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "生活", color: "peach", modifiedAt: Date(timeIntervalSince1970: 0)),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "代码", color: "mint", modifiedAt: Date(timeIntervalSince1970: 0)),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "灵感", color: "pink", modifiedAt: Date(timeIntervalSince1970: 0))
    ]
}

public enum AIFormat: String, Codable, CaseIterable, Sendable {
    case openAI = "OpenAI", claude = "Claude"
    public var defaultBaseURL: String { self == .openAI ? "https://api.openai.com/v1" : "https://api.anthropic.com/v1" }
}

public struct AIConfiguration: Codable, Equatable, Sendable {
    public var format: AIFormat = .openAI
    public var baseURL: String = "https://api.openai.com/v1"
    public var model: String = ""
    public var autoClassify: Bool = false
    public init() {}
    public var isConfigured: Bool { !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && URL(string: baseURL)?.host != nil }
}

public struct Preferences: Codable, Equatable, Sendable {
    /// Zero means forever. All records share this rule unless explicitly protected.
    public var retentionDays: Int = 30
    public var appearance: String = "system"
    public var capturePaused: Bool = false
    public var moveToFrontAfterUse: Bool = true
    public var ignoredApps: [String] = []
    public var ai = AIConfiguration()
    public var iCloudEnabled = false
    public var language = AppLanguage.system
    public var shortcuts = ShortcutPreferences()
    public init() {}
    enum CodingKeys: String, CodingKey { case retentionDays, appearance, capturePaused, ignoredApps, ai, iCloudEnabled, language, shortcuts
        // Preserve the stored preference from versions that promoted only after paste.
        case moveToFrontAfterUse = "moveToFrontAfterPaste"
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        retentionDays = try values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 0
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        capturePaused = try values.decodeIfPresent(Bool.self, forKey: .capturePaused) ?? false
        moveToFrontAfterUse = try values.decodeIfPresent(Bool.self, forKey: .moveToFrontAfterUse) ?? true
        ignoredApps = try values.decodeIfPresent([String].self, forKey: .ignoredApps) ?? []
        ai = try values.decodeIfPresent(AIConfiguration.self, forKey: .ai) ?? AIConfiguration()
        iCloudEnabled = try values.decodeIfPresent(Bool.self, forKey: .iCloudEnabled) ?? false
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        shortcuts = try values.decodeIfPresent(ShortcutPreferences.self, forKey: .shortcuts) ?? ShortcutPreferences()
    }
}

public struct SearchPlan: Codable, Sendable {
    public var keywords: [String]
    public var startDate: String?
    public var endDate: String?
    public init(keywords: [String], startDate: String? = nil, endDate: String? = nil) {
        self.keywords = keywords; self.startDate = startDate; self.endDate = endDate
    }
}

public struct MemorySearchResult: Sendable {
    public var records: [Memory]
    public var answer: String
    public init(records: [Memory], answer: String) { self.records = records; self.answer = answer }
}
