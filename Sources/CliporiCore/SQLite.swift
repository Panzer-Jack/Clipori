import Foundation
import CSQLite

struct DatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { LF("本地数据库：%@", message) }
}

enum SQLValue { case text(String), number(Double), blob(Data), null }

/// Confined to MemoryStore's actor; never called directly from the UI.
final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = DatabaseError(message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? L("无法打开文件"))
            if let handle { sqlite3_close(handle) }
            throw error
        }
        sqlite3_busy_timeout(handle, 5_000)
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String, _ values: [SQLValue] = []) throws { _ = try rows(sql, values) }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        guard let statement else { throw error() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string): result = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
            case .number(let number): result = sqlite3_bind_double(statement, index, number)
            case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob64(statement, index, $0.baseAddress, UInt64(data.count), transient) }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { sqlite3_finalize(statement); throw error() }
        }
        return statement
    }
    func data(_ sql: String, _ values: [SQLValue] = []) throws -> Data? {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw error() }
        guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
    func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [[String]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw error() }
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                // SQLite's default text conversion rounds REAL values to 15 significant digits.
                // Preserve timestamps exactly when they participate in sync acknowledgements.
                if sqlite3_column_type(statement, index) == SQLITE_FLOAT { return String(sqlite3_column_double(statement, index)) }
                return sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
            })
        }
        return rows
    }
    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try operation(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func error() -> DatabaseError { DatabaseError(message: String(cString: sqlite3_errmsg(handle))) }
}
