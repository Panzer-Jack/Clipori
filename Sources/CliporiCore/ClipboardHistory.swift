import Foundation

extension MemoryStore {
    static func installClipboardHistorySchema(_ db: SQLiteConnection) throws {
        try db.transaction {
            // Keep the original eight-column table compatible with installed older apps.
            try db.execute("CREATE TABLE IF NOT EXISTS memory_recency (id TEXT PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE, last_used REAL NOT NULL)")
            if try db.rows("PRAGMA table_info(memories)").contains(where: { $0[1] == "last_used" }) {
                try db.execute("INSERT OR REPLACE INTO memory_recency SELECT id, last_used FROM memories WHERE last_used IS NOT NULL")
                try db.execute("DROP INDEX IF EXISTS memory_recent")
                try db.execute("DROP INDEX IF EXISTS memory_category_recent")
                try db.execute("ALTER TABLE memories DROP COLUMN last_used")
            }
            try db.execute("CREATE INDEX IF NOT EXISTS memory_body ON memories(body)")
        }
    }

    /// Deduplicate clipboard captures only. Explicitly created or edited notes remain independent.
    /// Comparing UTF-8 preserves whitespace and distinguishes Unicode normalization forms.
    @discardableResult
    public func captureText(_ incoming: Memory) throws -> Memory {
        try db.transaction {
            guard incoming.kind != .image else { try write(incoming); return incoming }
            let matches = try decodeRows(db.rows("SELECT m.payload FROM memories m LEFT JOIN memory_recency r ON r.id=m.id WHERE m.body=? AND json_extract(m.payload, '$.kind')!='image' ORDER BY COALESCE(r.last_used, m.created) DESC, m.id DESC", [.text(incoming.body)]))
            if let existing = matches.first(where: { $0.body.utf8.elementsEqual(incoming.body.utf8) }) {
                return existing
            }
            try write(incoming)
            return incoming
        }
    }

    /// Recency is local presentation state, separate from edits and retention dates.
    /// INSERT ... SELECT cannot resurrect a record deleted while a paste was in flight.
    @discardableResult
    public func markUsed(id: UUID, at date: Date = Date()) throws -> Bool {
        guard try !db.rows("SELECT id FROM memories WHERE id=?", [.text(id.uuidString)]).isEmpty else { return false }
        try db.execute("INSERT INTO memory_recency SELECT id, MAX(created, ?) FROM memories WHERE id=? ON CONFLICT(id) DO UPDATE SET last_used=MAX(memory_recency.last_used, excluded.last_used)", [
            .number(date.timeIntervalSince1970), .text(id.uuidString)
        ])
        return true
    }
}
