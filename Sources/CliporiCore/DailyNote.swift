import Foundation

public struct DailyTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var evidence: [DailyNoteEvidence]?

    public init(id: UUID = UUID(), title: String = "", isCompleted: Bool = false) {
        self.id = id; self.title = title; self.isCompleted = isCompleted
    }
}

public struct DailyItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String
    public var isPinned: Bool
    /// Used for an item without subtasks. Otherwise completion is derived from its tasks.
    public var isCompleted: Bool
    public var tasks: [DailyTask]
    public var evidence: [DailyNoteEvidence]?

    public init(id: UUID = UUID(), title: String = "", note: String = "", isPinned: Bool = false,
                isCompleted: Bool = false, tasks: [DailyTask] = []) {
        self.id = id; self.title = title; self.note = note; self.isPinned = isPinned
        self.isCompleted = isCompleted; self.tasks = tasks
    }

    public var completed: Bool { tasks.isEmpty ? isCompleted : tasks.allSatisfy(\.isCompleted) }
    public var carriesForward: Bool { isPinned && !completed }
}

/// Each day owns a value snapshot; matching item IDs never link mutable historical state.
public struct DailyNote: Identifiable, Codable, Equatable, Sendable {
    public var id: String { day }
    public let day: String
    public var items: [DailyItem]

    public init(day: String, items: [DailyItem] = []) { self.day = day; self.items = items }

    public func continuing(on day: String) -> DailyNote {
        DailyNote(day: day, items: items.filter(\.carriesForward))
    }
}

/// Gregorian civil dates keep ordering stable across locales and 23/25-hour DST days.
public enum DailyNoteDay {
    public static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    public static func date(for key: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = formatter(timeZone: timeZone)
        guard let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return date
    }

    public static func next(after key: String) -> String? {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        guard let date = date(for: key, timeZone: utc), let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        return self.key(for: next, timeZone: utc)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
}
