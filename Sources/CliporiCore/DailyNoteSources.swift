import Foundation

public struct DailyClipboardSource: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let content: String
    public let app: String
    public let modifiedAt: Date
}

public struct DailyClipboardContext: Sendable {
    public let day: String
    public let sources: [DailyClipboardSource]
    public let totalRecords: Int
    public let isTruncated: Bool
}

extension MemoryStore {
    /// Read the selected civil day directly, independently of shelf pagination/search.
    /// Text only: manual notes, images and image pixels never enter this request.
    public func dailyClipboard(on day: String, timeZone: TimeZone = .current) throws -> DailyClipboardContext {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let start = DailyNoteDay.date(for: day, timeZone: timeZone),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { throw DailyNoteError.invalidDay }
        let filter = "created>=? AND created<? AND json_extract(payload, '$.kind')!='image' AND length(trim(body))>0 AND (json_extract(payload, '$.sourceBundleID') IS NOT NULL OR json_extract(payload, '$.source') NOT IN ('手动记录', 'Manual note'))"
        let values: [SQLValue] = [.number(start.timeIntervalSince1970), .number(end.timeIntervalSince1970)]
        let count = Int(try db.rows("SELECT count(*) FROM memories WHERE \(filter)", values).first?.first ?? "0") ?? 0
        let rows = try db.rows("SELECT payload FROM memories WHERE \(filter) ORDER BY created DESC, id DESC LIMIT 200", values)
        var sources: [DailyClipboardSource] = []
        var seen: Set<String> = []
        var budget = 32_000
        var truncated = count > rows.count
        for row in rows {
            let memory = try decoder.decode(Memory.self, from: Data(row[0].utf8))
            let content = memory.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(content).inserted else { continue }
            guard budget > 0 else { truncated = true; break }
            let excerpt = String(content.prefix(min(2400, budget)))
            if excerpt.count < content.count { truncated = true }
            budget -= excerpt.count
            sources.append(DailyClipboardSource(id: memory.id, title: String(memory.title.prefix(160)),
                                                content: excerpt, app: String(memory.displaySource.prefix(80)), modifiedAt: memory.modifiedAt))
        }
        return DailyClipboardContext(day: day, sources: sources, totalRecords: count, isTruncated: truncated)
    }

    /// A response to a deleted or edited clipboard record must not revive its old contents.
    public func unchangedDailySourceIDs(_ context: DailyClipboardContext) throws -> Set<UUID> {
        var ids: Set<UUID> = []
        for source in context.sources {
            if let latest = try record(id: source.id), latest.modifiedAt == source.modifiedAt,
               latest.body.contains(source.content), latest.title.hasPrefix(source.title) { ids.insert(source.id) }
        }
        return ids
    }
}
