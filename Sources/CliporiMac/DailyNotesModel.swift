import Foundation
import Combine
import CliporiCore

@MainActor
final class DailyNotesModel: ObservableObject {
    @Published private(set) var note: DailyNote?
    @Published private(set) var days: [String] = []
    @Published private(set) var today: String
    @Published private(set) var isLoading = false
    @Published private(set) var isDirty = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var deletedSnapshot: DailyNote?
    private let store: DailyNoteStore
    private let now: () -> Date
    private var revision = 0
    private var pendingSave: Task<Void, Never>?
    private var saving: Task<Bool, Never>?

    var isHistorical: Bool { note.map { $0.day != today } ?? false }

    init(store: DailyNoteStore, now: @escaping () -> Date = Date.init) {
        self.store = store; self.now = now; today = DailyNoteDay.key(for: now())
    }

    /// Flush the page being edited before carrying it forward, including overnight typing.
    func refreshToday() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        guard await flush() else { return }
        let day = DailyNoteDay.key(for: now())
        do {
            let current = try await store.ensureDay(day)
            let followToday = note == nil || (note?.day == today && today != day)
            days = try await store.days()
            today = day
            if followToday { note = current; deletedSnapshot = nil }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func selectDay(_ day: String) async {
        guard !isLoading, note?.day != day else { return }
        isLoading = true; defer { isLoading = false }
        guard await flush() else { return }
        do {
            guard let page = try await store.note(on: day) else { throw DailyNoteError.missingPage }
            note = page; deletedSnapshot = nil; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func addItem(title: String = "", note: String = "") -> UUID? {
        let item = DailyItem(title: title, note: note)
        guard edit({ $0.items.append(item) }) else { return nil }
        return item.id
    }

    func updateItem(_ id: UUID, _ update: (inout DailyItem) -> Void) {
        edit { page in
            guard let index = page.items.firstIndex(where: { $0.id == id }) else { return }
            update(&page.items[index])
        }
    }

    /// Apply reviewed suggestions to the current revision, never the AI's old snapshot.
    func applySuggestions(_ suggestions: [DailyNoteSuggestion], on day: String) -> Int? {
        guard !isLoading, note?.day == day else { return nil }
        var added = 0
        edit { added = $0.addSuggestions(suggestions) }
        return added
    }

    @discardableResult
    func addTask(to itemID: UUID, after taskID: UUID? = nil) -> UUID? {
        let task = DailyTask()
        guard !isLoading, note?.items.contains(where: { $0.id == itemID }) == true else { return nil }
        updateItem(itemID) { item in
            let index = taskID.flatMap { id in item.tasks.firstIndex { $0.id == id } }.map { $0 + 1 } ?? item.tasks.count
            item.tasks.insert(task, at: index)
            item.isCompleted = false
        }
        return task.id
    }

    func updateTask(_ taskID: UUID, in itemID: UUID, _ update: (inout DailyTask) -> Void) {
        updateItem(itemID) { item in
            guard let index = item.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            update(&item.tasks[index])
        }
    }

    func deleteItem(_ id: UUID) {
        guard !isLoading else { return }
        let previous = note
        edit { $0.items.removeAll { $0.id == id } }
        deletedSnapshot = previous
    }

    func deleteTask(_ id: UUID, in itemID: UUID) {
        guard !isLoading else { return }
        let previous = note
        updateItem(itemID) { $0.tasks.removeAll { $0.id == id } }
        deletedSnapshot = previous
    }

    func undoDeletion() {
        guard !isLoading, let snapshot = deletedSnapshot, snapshot.day == note?.day else { return }
        note = snapshot; deletedSnapshot = nil; changed()
    }

    func moveItem(_ id: UUID, before target: UUID) {
        edit { page in Self.move(id, before: target, in: &page.items) }
    }

    func moveTask(_ id: UUID, before target: UUID, in itemID: UUID) {
        updateItem(itemID) { Self.move(id, before: target, in: &$0.tasks) }
    }

    private static func move<T: Identifiable>(_ id: T.ID, before target: T.ID, in items: inout [T]) {
        guard id != target, let source = items.firstIndex(where: { $0.id == id }), items.contains(where: { $0.id == target }) else { return }
        let item = items.remove(at: source)
        let destination = items.firstIndex(where: { $0.id == target })!
        items.insert(item, at: destination)
    }

    @discardableResult
    private func edit(_ update: (inout DailyNote) -> Void) -> Bool {
        guard !isLoading, var page = note else { return false }
        update(&page)
        guard page != note else { return false }
        // Only offer undo until the next edit, so it never discards subsequent typing.
        deletedSnapshot = nil
        note = page; changed(); return true
    }

    private func changed() {
        revision += 1; isDirty = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await self?.flush()
        }
    }

    /// Single-flight saves prevent an older autosave from overwriting a newer edit.
    /// Navigation and close wait until the latest revision is safely persisted.
    @discardableResult
    func flush() async -> Bool {
        pendingSave?.cancel(); pendingSave = nil
        if let saving {
            guard await saving.value else { return false }
            return await flush()
        }
        guard isDirty, let snapshot = note else { return true }
        let version = revision
        let operation = Task { [self] in
            defer { saving = nil }
            do {
                try await store.save(snapshot)
                if revision == version { isDirty = false }
                errorMessage = nil
                return true
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        saving = operation
        guard await operation.value else { return false }
        return await flush()
    }
}
