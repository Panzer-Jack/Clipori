import Foundation

/// Separate from clipboard retention, clearing and sync. All writes are actor-confined.
public actor DailyNoteStore {
    private let db: SQLiteConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteConnection(path: url.path)
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("CREATE TABLE IF NOT EXISTS daily_notes (day TEXT PRIMARY KEY, payload TEXT NOT NULL)")
    }

    public func days() throws -> [String] {
        try db.rows("SELECT day FROM daily_notes ORDER BY day DESC").map { $0[0] }
    }

    public func note(on day: String) throws -> DailyNote? {
        guard let payload = try db.rows("SELECT payload FROM daily_notes WHERE day=?", [.text(day)]).first?.first else { return nil }
        return try decoder.decode(DailyNote.self, from: Data(payload.utf8))
    }

    /// Idempotent and atomic, including days missed while the app was closed.
    /// Existing pages are never regenerated from a subsequently edited historical page.
    @discardableResult
    public func ensureDay(_ day: String) throws -> DailyNote {
        try validate(day)
        return try db.transaction {
            if let existing = try note(on: day) { return existing }
            let previous = try db.rows("SELECT payload FROM daily_notes WHERE day<? ORDER BY day DESC LIMIT 1", [.text(day)]).first?.first
            guard let previous else {
                let initial = DailyNote(day: day)
                try write(initial)
                return initial
            }
            var current = try decoder.decode(DailyNote.self, from: Data(previous.utf8))
            while current.day < day {
                guard let next = DailyNoteDay.next(after: current.day) else { throw DailyNoteError.invalidDay }
                current = current.continuing(on: next)
                try write(current)
            }
            return current
        }
    }

    public func save(_ note: DailyNote) throws {
        try validate(note.day)
        guard try self.note(on: note.day) != nil else { throw DailyNoteError.missingPage }
        try write(note)
    }

    private func write(_ note: DailyNote) throws {
        let payload = String(decoding: try encoder.encode(note), as: UTF8.self)
        try db.execute("INSERT OR REPLACE INTO daily_notes (day, payload) VALUES (?, ?)", [.text(note.day), .text(payload)])
    }

    private func validate(_ day: String) throws {
        guard DailyNoteDay.date(for: day, timeZone: TimeZone(secondsFromGMT: 0)!) != nil else { throw DailyNoteError.invalidDay }
    }
}

public enum DailyNoteError: LocalizedError {
    case invalidDay, missingPage
    public var errorDescription: String? {
        switch self {
        case .invalidDay: return L("备忘录日期无效。")
        case .missingPage: return L("这一天的备忘录不存在。")
        }
    }
}
