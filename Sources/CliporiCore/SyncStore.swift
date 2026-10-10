import Foundation

/// Only records, categories and deletion markers cross devices. Preferences and secrets stay local.
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case memory, category }
    public var id: UUID
    public var kind: Kind
    public var modifiedAt: Date
    public var deleted: Bool
    public var payload: Data?
    public var key: String { "\(kind.rawValue)-\(id.uuidString)" }

    public init(memory: Memory) throws {
        id = memory.id; kind = .memory; modifiedAt = memory.modifiedAt; deleted = false
        payload = try Self.encode(memory)
    }
    public init(category: MemoryCategory) throws {
        id = category.id; kind = .category; modifiedAt = category.modifiedAt; deleted = false
        payload = try Self.encode(category)
    }
    public init(deleting id: UUID, kind: Kind, at date: Date) {
        self.id = id; self.kind = kind
        // Deletions are stored as SQLite epoch seconds; use millisecond precision across date epochs.
        modifiedAt = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
        deleted = true; payload = nil
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
    /// Deletion is terminal for an ID. Equal-clock edits use a deterministic tie break.
    func wins(over other: SyncEnvelope) -> Bool {
        if deleted != other.deleted { return deleted }
        if modifiedAt != other.modifiedAt { return modifiedAt > other.modifiedAt }
        return (payload ?? Data()).lexicographicallyPrecedes(other.payload ?? Data())
    }
}

extension MemoryStore {
    static func installSyncSchema(_ db: SQLiteConnection) throws {
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS sync_outbox (key TEXT PRIMARY KEY)")
            try db.execute("CREATE TABLE IF NOT EXISTS sync_fields (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            for (table, kind) in [("memories", "memory"), ("categories", "category")] {
                for operation in ["INSERT", "UPDATE"] {
                    try db.execute("CREATE TRIGGER IF NOT EXISTS sync_\(table)_\(operation) AFTER \(operation) ON \(table) BEGIN INSERT OR IGNORE INTO sync_outbox VALUES ('\(kind)-' || NEW.id); END")
                }
            }
            for operation in ["INSERT", "UPDATE"] {
                try db.execute("CREATE TRIGGER IF NOT EXISTS sync_tombstones_\(operation) AFTER \(operation) ON tombstones BEGIN INSERT OR IGNORE INTO sync_outbox VALUES (NEW.kind || '-' || NEW.id); END")
            }
            if try db.rows("SELECT value FROM metadata WHERE key='sync-schema'").isEmpty {
                try db.execute("INSERT OR IGNORE INTO sync_outbox SELECT 'memory-' || id FROM memories")
                try db.execute("INSERT OR IGNORE INTO sync_outbox SELECT 'category-' || id FROM categories")
                try db.execute("INSERT OR IGNORE INTO sync_outbox SELECT kind || '-' || id FROM tombstones")
                try db.execute("INSERT INTO metadata VALUES ('sync-schema','1')")
            }
        }
    }

    public func syncPending(limit: Int = 100) throws -> [SyncEnvelope] {
        // Images are local in this release. Do not upload metadata pointing to pixels absent on iPhone.
        // Filter before LIMIT so a page of local images cannot starve text/category synchronization.
        try db.rows("SELECT key FROM sync_outbox WHERE key NOT LIKE 'memory-%' OR NOT EXISTS (SELECT 1 FROM memories WHERE id=substr(sync_outbox.key, 8) AND json_extract(payload, '$.kind')='image') ORDER BY rowid LIMIT ?", [.number(Double(limit))]).compactMap { try syncEnvelope(key: $0[0]) }
    }
    public func syncEnvelope(key: String) throws -> SyncEnvelope? {
        guard let dash = key.firstIndex(of: "-"), let kind = SyncEnvelope.Kind(rawValue: String(key[..<dash])),
              let id = UUID(uuidString: String(key[key.index(after: dash)...])) else { return nil }
        if let row = try db.rows("SELECT deleted FROM tombstones WHERE id=? AND kind=?", [.text(id.uuidString), .text(kind.rawValue)]).first {
            return .init(deleting: id, kind: kind, at: Date(timeIntervalSince1970: Double(row[0]) ?? 0))
        }
        switch kind {
        case .memory: return try record(id: id).map { try SyncEnvelope(memory: $0) }
        case .category:
            guard let row = try db.rows("SELECT payload FROM categories WHERE id=?", [.text(id.uuidString)]).first else { return nil }
            return try SyncEnvelope(category: decoder.decode(MemoryCategory.self, from: Data(row[0].utf8)))
        }
    }
    /// An upload acknowledgement may arrive after another local edit. Never clear that edit's outbox entry.
    public func syncAcknowledge(_ uploaded: SyncEnvelope, systemFields: Data) throws {
        try db.transaction {
            try syncSaveFields(key: uploaded.key, data: systemFields)
            if try syncEnvelope(key: uploaded.key) == uploaded { try db.execute("DELETE FROM sync_outbox WHERE key=?", [.text(uploaded.key)]) }
        }
    }
    public func syncFields(key: String) throws -> Data? {
        try db.rows("SELECT value FROM sync_fields WHERE key=?", [.text(key)]).first.flatMap { Data(base64Encoded: $0[0]) }
    }
    public func syncForgetFields(key: String) throws {
        try db.execute("DELETE FROM sync_fields WHERE key=?", [.text(key)])
    }
    func syncSaveFields(key: String, data: Data) throws {
        try db.execute("INSERT OR REPLACE INTO sync_fields VALUES (?, ?)", [.text(key), .text(data.base64EncodedString())])
    }
    public func syncMetadata(_ key: String) throws -> Data? {
        try db.rows("SELECT value FROM metadata WHERE key=?", [.text("cloud-" + key)]).first.flatMap { Data(base64Encoded: $0[0]) }
    }
    public func setSyncMetadata(_ key: String, data: Data) throws {
        try db.execute("INSERT OR REPLACE INTO metadata VALUES (?, ?)", [.text("cloud-" + key), .text(data.base64EncodedString())])
    }

    @discardableResult
    public func mergeRemote(_ incoming: SyncEnvelope, systemFields: Data = Data()) throws -> Bool {
        try db.transaction {
            if !systemFields.isEmpty { try syncSaveFields(key: incoming.key, data: systemFields) }
            let local = try syncEnvelope(key: incoming.key)
            if let local, local != incoming, !incoming.wins(over: local) {
                try db.execute("INSERT OR IGNORE INTO sync_outbox VALUES (?)", [.text(incoming.key)])
                return false
            }
            if incoming.deleted {
                if incoming.kind == .memory {
                    try db.execute("DELETE FROM memories WHERE id=?", [.text(incoming.id.uuidString)])
                    try db.execute("DELETE FROM memory_search WHERE id=?", [.text(incoming.id.uuidString)])
                } else {
                    try db.execute("DELETE FROM categories WHERE id=?", [.text(incoming.id.uuidString)])
                    let affected = try db.rows("SELECT payload FROM memories WHERE category=?", [.text(incoming.id.uuidString)])
                    for row in affected {
                        var memory = try decoder.decode(Memory.self, from: Data(row[0].utf8))
                        memory.categoryID = nil; memory.assignment = .manual
                        memory.modifiedAt = max(memory.modifiedAt, incoming.modifiedAt)
                        try write(memory)
                    }
                }
                try db.execute("INSERT OR REPLACE INTO tombstones VALUES (?, ?, ?)", [.text(incoming.id.uuidString), .text(incoming.kind.rawValue), .number(incoming.modifiedAt.timeIntervalSince1970)])
            } else {
                guard let payload = incoming.payload else { throw DatabaseError(message: L("同步内容不完整")) }
                switch incoming.kind {
                case .memory:
                    var memory = try decoder.decode(Memory.self, from: payload)
                    guard memory.id == incoming.id, memory.modifiedAt == incoming.modifiedAt else { throw DatabaseError(message: L("同步记录标识不一致")) }
                    if let category = memory.categoryID,
                       try !db.rows("SELECT id FROM tombstones WHERE id=? AND kind='category'", [.text(category.uuidString)]).isEmpty {
                        memory.categoryID = nil; memory.assignment = .manual
                    }
                    // A late automatic classification on another device cannot undo a manual choice.
                    if let current = try record(id: memory.id), current.assignment == .manual, memory.assignment == .automatic {
                        memory.categoryID = current.categoryID; memory.assignment = .manual
                    }
                    try write(memory)
                case .category:
                    let category = try decoder.decode(MemoryCategory.self, from: payload)
                    guard category.id == incoming.id, category.modifiedAt == incoming.modifiedAt else { throw DatabaseError(message: L("同步分类标识不一致")) }
                    try writeCategory(category)
                }
            }
            if try syncEnvelope(key: incoming.key) == incoming { try db.execute("DELETE FROM sync_outbox WHERE key=?", [.text(incoming.key)]) }
            return local != incoming
        }
    }
}
