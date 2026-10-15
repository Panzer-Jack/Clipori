import Foundation
import NaturalLanguage

public actor MemoryStore {
    let db: SQLiteConnection
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteConnection(path: url.path)
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA foreign_keys = ON")
        try db.execute("CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY, body TEXT NOT NULL, title TEXT NOT NULL, created REAL NOT NULL, modified REAL NOT NULL, category TEXT, protected INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL)")
        try db.execute("CREATE INDEX IF NOT EXISTS memory_date ON memories(created DESC, id)")
        try db.execute("CREATE INDEX IF NOT EXISTS memory_category ON memories(category, created DESC)")
        try db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS memory_search USING fts5(id UNINDEXED, terms, tokenize='unicode61')")
        try db.execute("CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        try db.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try db.execute("CREATE TABLE IF NOT EXISTS tombstones (id TEXT PRIMARY KEY, kind TEXT NOT NULL, deleted REAL NOT NULL)")
        try db.execute("CREATE TABLE IF NOT EXISTS image_attachments (id TEXT PRIMARY KEY, png BLOB NOT NULL, thumbnail BLOB NOT NULL)")
        try Self.installClipboardHistorySchema(db)
        try Self.installSyncSchema(db)
        if try db.rows("SELECT value FROM metadata WHERE key='initialized'").isEmpty {
            let encoder = JSONEncoder()
            try db.transaction {
                for category in MemoryCategory.defaults {
                    try db.execute("INSERT OR IGNORE INTO categories VALUES (?, ?)", [.text(category.id.uuidString), .text(String(decoding: try encoder.encode(category), as: UTF8.self))])
                }
                try db.execute("INSERT INTO metadata VALUES ('initialized','1')")
                try db.execute("INSERT INTO metadata VALUES ('preferences', ?)", [.text(String(decoding: try encoder.encode(Preferences()), as: UTF8.self))])
            }
        }
    }

    public func save(_ record: Memory) throws {
        try db.transaction { try write(record) }
    }

    /// Apply a manual category to the latest versions in one transaction, without rewriting text indexes.
    /// Missing records were deleted while the user was dragging and must not be recreated.
    public func assign(ids: [UUID], to categoryID: UUID?) throws -> [Memory] {
        try db.transaction {
            if let categoryID, try db.rows("SELECT id FROM categories WHERE id=?", [.text(categoryID.uuidString)]).isEmpty {
                throw CategoryAssignmentError.missingCategory
            }
            var updated: [Memory] = []
            var seen: Set<UUID> = []
            for id in ids where seen.insert(id).inserted {
                guard var latest = try record(id: id) else { continue }
                latest.categoryID = categoryID; latest.assignment = .manual; latest.modifiedAt = Date()
                let payload = String(decoding: try encoder.encode(latest), as: UTF8.self)
                try db.execute("UPDATE memories SET category=?, modified=?, payload=? WHERE id=?", [
                    categoryID.map { .text($0.uuidString) } ?? .null,
                    .number(latest.modifiedAt.timeIntervalSince1970), .text(payload), .text(id.uuidString)
                ])
                updated.append(latest)
            }
            return updated
        }
    }

    /// Editors update existing records without resurrecting one deleted by cleanup or another window.
    public func saveEdit(_ record: Memory, isNew: Bool) throws -> Bool {
        try db.transaction {
            if !isNew {
                if try db.rows("SELECT id FROM memories WHERE id=?", [.text(record.id.uuidString)]).isEmpty { return false }
            }
            try write(record)
            return true
        }
    }

    func write(_ record: Memory) throws {
        // A delayed editor, pin toggle or AI task must not revive a deleted identity.
        guard try db.rows("SELECT id FROM tombstones WHERE id=? AND kind='memory'", [.text(record.id.uuidString)]).isEmpty else {
            throw DatabaseError(message: L("原记录已被删除，请复制内容后另建备忘。"))
        }
        let payload = String(decoding: try encoder.encode(record), as: UTF8.self)
        // Update in place so edits do not cascade-delete local recency metadata.
        // A separate UPDATE also preserves the sync triggers' own conflict handling.
        let exists = try !db.rows("SELECT id FROM memories WHERE id=?", [.text(record.id.uuidString)]).isEmpty
        let sql = exists
            ? "UPDATE memories SET body=?2, title=?3, created=?4, modified=?5, category=?6, protected=?7, payload=?8 WHERE id=?1"
            : "INSERT INTO memories (id, body, title, created, modified, category, protected, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        try db.execute(sql, [
            .text(record.id.uuidString), .text(record.body), .text(record.title),
            .number(record.createdAt.timeIntervalSince1970), .number(record.modifiedAt.timeIntervalSince1970),
            record.categoryID.map { .text($0.uuidString) } ?? .null, .number(record.keepForever ? 1 : 0), .text(payload)
        ])
        try db.execute("DELETE FROM memory_search WHERE id=?", [.text(record.id.uuidString)])
        try db.execute("INSERT INTO memory_search(id, terms) VALUES (?, ?)", [.text(record.id.uuidString), .text(Self.searchTerms(record.title + " " + record.body + " " + record.source))])
    }

    public func record(id: UUID) throws -> Memory? {
        try decodeRows(db.rows("SELECT payload FROM memories WHERE id=?", [.text(id.uuidString)])).first
    }

    public func list(query: String = "", categoryID: UUID? = nil, uncategorized: Bool = false,
                     protectedOnly: Bool = false, limit: Int = 80, offset: Int = 0) throws -> [Memory] {
        var clauses: [String] = []; var values: [SQLValue] = []
        if let categoryID { clauses.append("category=?"); values.append(.text(categoryID.uuidString)) }
        if uncategorized { clauses.append("category IS NULL") }
        if protectedOnly { clauses.append("protected=1") }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            clauses.append("(body LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\')")
            let escaped = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            values += [.text("%\(escaped)%"), .text("%\(escaped)%")]
        }
        let filter = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        values += [.number(Double(max(1, min(limit, 500)))), .number(Double(max(0, offset)))]
        return try decodeRows(db.rows("SELECT m.payload FROM memories m LEFT JOIN memory_recency r ON r.id=m.id\(filter) ORDER BY COALESCE(r.last_used, m.created) DESC, m.id DESC LIMIT ? OFFSET ?", values))
    }

    public func candidates(plan: SearchPlan, categoryID: UUID? = nil, limit: Int = 50) throws -> [Memory] {
        let terms = plan.keywords.flatMap { Self.searchTerms($0).split(separator: " ").map(String.init) }
        let unique = Array(Set(terms.filter { !$0.isEmpty })).sorted().prefix(60)
        var values: [SQLValue] = []; var clauses: [String] = []
        let useFTS = !unique.isEmpty
        if useFTS {
            clauses.append("memory_search MATCH ?")
            values.append(.text(unique.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        if let start = plan.startDate.flatMap({ formatter.date(from: $0) }) { clauses.append("m.created>=?"); values.append(.number(start.timeIntervalSince1970)) }
        if let end = plan.endDate.flatMap({ formatter.date(from: $0) }),
           let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: end) {
            clauses.append("m.created<?"); values.append(.number(nextDay.timeIntervalSince1970))
        }
        if let categoryID { clauses.append("m.category=?"); values.append(.text(categoryID.uuidString)) }
        let join = useFTS ? " JOIN memory_search ON memory_search.id=m.id" : ""
        let filter = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let order = useFTS ? "bm25(memory_search), m.created DESC" : "m.created DESC"
        values.append(.number(Double(limit)))
        return try decodeRows(db.rows("SELECT m.payload FROM memories m\(join)\(filter) ORDER BY \(order) LIMIT ?", values))
    }

    public func count() throws -> Int { Int(try db.rows("SELECT count(*) FROM memories").first?.first ?? "0") ?? 0 }

    public func delete(id: UUID, at date: Date = Date()) throws {
        try db.transaction {
            try db.execute("DELETE FROM memories WHERE id=?", [.text(id.uuidString)])
            try db.execute("DELETE FROM memory_search WHERE id=?", [.text(id.uuidString)])
            try db.execute("INSERT OR REPLACE INTO tombstones VALUES (?, 'memory', ?)", [.text(id.uuidString), .number(date.timeIntervalSince1970)])
        }
    }

    /// Explicitly clears all saved memories, including pins and image attachments.
    /// Keep categories, preferences and deletion markers so sync cannot bring old records back.
    @discardableResult
    public func deleteAllMemories(at date: Date = Date()) throws -> Int {
        try db.transaction {
            let deletedCount = try count()
            try db.execute("INSERT OR REPLACE INTO tombstones SELECT id, 'memory', ? FROM memories", [.number(date.timeIntervalSince1970)])
            try db.execute("DELETE FROM memory_search")
            try db.execute("DELETE FROM memories")
            try db.execute("DELETE FROM image_attachments")
            return deletedCount
        }
    }

    @discardableResult
    public func clean(retentionDays: Int, now: Date = Date()) throws -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970
        let filter = "protected=0 AND created<? AND (category IS NULL OR category NOT IN (SELECT id FROM categories WHERE json_extract(payload, '$.isPinboard')=1))"
        let expired = try db.rows("SELECT id FROM memories WHERE \(filter)", [.number(cutoff)])
        try db.transaction {
            for row in expired {
                try db.execute("DELETE FROM memory_search WHERE id=?", [.text(row[0])])
                try db.execute("INSERT OR REPLACE INTO tombstones VALUES (?, 'memory', ?)", [.text(row[0]), .number(now.timeIntervalSince1970)])
            }
            try db.execute("DELETE FROM memories WHERE \(filter)", [.number(cutoff)])
        }
        return expired.count
    }

    public func categories() throws -> [MemoryCategory] {
        let categories = try db.rows("SELECT payload FROM categories ORDER BY rowid").map { try decoder.decode(MemoryCategory.self, from: Data($0[0].utf8)) }
        guard let value = try db.rows("SELECT value FROM metadata WHERE key='category-order'").first?.first else { return categories }
        let ids = try decoder.decode([UUID].self, from: Data(value.utf8))
        return Self.orderedCategories(categories, ids: ids)
    }
    /// Device-local display order. Keep current category contents, omit deleted IDs,
    /// and append categories created since the drag began.
    @discardableResult
    public func reorderCategories(_ ids: [UUID]) throws -> [MemoryCategory] {
        try db.transaction {
            let ordered = Self.orderedCategories(try categories(), ids: ids)
            let value = String(decoding: try encoder.encode(ordered.map(\.id)), as: UTF8.self)
            try db.execute("INSERT OR REPLACE INTO metadata VALUES ('category-order', ?)", [.text(value)])
            return ordered
        }
    }
    private static func orderedCategories(_ categories: [MemoryCategory], ids: [UUID]) -> [MemoryCategory] {
        var remaining = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let ordered = ids.compactMap { remaining.removeValue(forKey: $0) }
        return ordered + categories.filter { remaining[$0.id] != nil }
    }
    public func saveCategory(_ category: MemoryCategory) throws {
        try db.transaction { try writeCategory(category) }
    }
    func writeCategory(_ category: MemoryCategory) throws {
        guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let id = SQLValue.text(category.id.uuidString)
        let payload = SQLValue.text(String(decoding: try encoder.encode(category), as: UTF8.self))
        // An UPSERT's conflict policy can override the sync trigger's INSERT OR IGNORE.
        // Separate UPDATE preserves both category order and an already queued sync change.
        if try db.rows("SELECT id FROM categories WHERE id=?", [id]).isEmpty {
            try db.execute("INSERT INTO categories VALUES (?, ?)", [id, payload])
        } else {
            try db.execute("UPDATE categories SET payload=? WHERE id=?", [payload, id])
        }
    }
    public func deleteCategory(id: UUID) throws {
        let records = try decodeRows(db.rows("SELECT payload FROM memories WHERE category=?", [.text(id.uuidString)]))
        try db.transaction {
            for var record in records {
                record.categoryID = nil; record.assignment = .manual; record.modifiedAt = Date()
                try write(record)
            }
            try db.execute("DELETE FROM categories WHERE id=?", [.text(id.uuidString)])
            try db.execute("INSERT OR REPLACE INTO tombstones VALUES (?, 'category', ?)", [.text(id.uuidString), .number(Date().timeIntervalSince1970)])
        }
    }

    /// A delayed AI response must never recreate a deleted record or undo a user's edit/category choice.
    @discardableResult
    public func applyClassification(id: UUID, categoryID: UUID?, expectedModifiedAt: Date) throws -> Bool {
        guard var record = try record(id: id), record.modifiedAt == expectedModifiedAt, record.assignment != .manual else { return false }
        if let categoryID, try !categories().contains(where: { $0.id == categoryID && !$0.isPinboard }) { return false }
        record.categoryID = categoryID; record.assignment = .automatic; record.modifiedAt = Date()
        try save(record); return true
    }

    public func pendingClassification(limit: Int = 20) throws -> [Memory] {
        // Only JSON metadata is inspected; the persisted classification state survives restarts.
        try decodeRows(db.rows("SELECT payload FROM memories WHERE json_extract(payload, '$.assignment')='none' AND (json_extract(payload, '$.kind')!='image' OR length(trim(title || body))>0) ORDER BY created DESC LIMIT ?", [.number(Double(limit))]))
    }

    /// A snapshot for a user-requested batch, including earlier AI attempts with no match.
    /// Manual choices (including an explicit unclassified choice) remain untouched.
    public func unclassifiedRecordIDs() throws -> [UUID] {
        try db.rows("SELECT id FROM memories WHERE \(Self.unclassifiedFilter) ORDER BY created DESC, id DESC")
            .compactMap { $0.first.flatMap(UUID.init(uuidString:)) }
    }
    public func unclassifiedCount() throws -> Int {
        Int(try db.rows("SELECT count(*) FROM memories WHERE \(Self.unclassifiedFilter)").first?.first ?? "0") ?? 0
    }
    private static let unclassifiedFilter = "category IS NULL AND json_extract(payload, '$.assignment')!='manual' AND (json_extract(payload, '$.kind')!='image' OR length(trim(title || body, char(9) || char(10) || char(13) || ' '))>0)"

    public func preferences() throws -> Preferences {
        guard let value = try db.rows("SELECT value FROM metadata WHERE key='preferences'").first?.first else {
            // Existing installs without an explicit settings row used forever. Preserve their history.
            var legacy = Preferences(); legacy.retentionDays = 0; return legacy
        }
        return try decoder.decode(Preferences.self, from: Data(value.utf8))
    }
    public func savePreferences(_ preferences: Preferences) throws {
        try db.execute("INSERT OR REPLACE INTO metadata VALUES ('preferences', ?)", [.text(String(decoding: try encoder.encode(preferences), as: UTF8.self))])
    }

    func decodeRows(_ rows: [[String]]) throws -> [Memory] {
        try rows.map { try decoder.decode(Memory.self, from: Data($0[0].utf8)) }
    }

    static func searchTerms(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text
        var terms: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            terms.append(token)
            let characters = Array(token)
            if characters.contains(where: { $0.unicodeScalars.contains { $0.value >= 0x3400 && $0.value <= 0x9FFF } }), characters.count > 1 {
                for index in 0..<(characters.count - 1) { terms.append(String(characters[index...index+1])) }
            }
            return true
        }
        return terms.joined(separator: " ")
    }
}

private enum CategoryAssignmentError: LocalizedError {
    case missingCategory
    var errorDescription: String? { L("这个分类已被删除，请选择其他分类。") }
}
