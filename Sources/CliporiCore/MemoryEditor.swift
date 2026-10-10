import Foundation
import Combine

@MainActor
public final class MemoryEditor: ObservableObject, Identifiable {
    public nonisolated let id: UUID
    @Published public var record: Memory
    @Published public var saveState = L("已保存")
    private let store: MemoryStore
    private let onSave: @MainActor () async -> Void
    private var pendingSave: Task<Void, Never>?
    private var generation = 0
    private var persisted = false
    private var dirty = false
    private var discarded = false
    public init(record: Memory?, store: MemoryStore, onSave: @escaping @MainActor () async -> Void = {}) {
        let initial = record ?? Memory(body: "")
        self.record = initial; id = initial.id
        self.store = store; self.onSave = onSave; persisted = record != nil
    }
    public func changed() {
        guard !discarded else { return }
        generation += 1; dirty = true; saveState = L("正在保存…")
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }
    @discardableResult
    public func flush() async -> Bool {
        guard !discarded else { return true }
        guard dirty else { return true }
        guard persisted || !record.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !record.title.isEmpty else { saveState = L("尚未输入"); return true }
        let version = generation
        var snapshot = record; snapshot.modifiedAt = Date()
        if snapshot.assignment != .manual { snapshot.assignment = .none; snapshot.categoryID = nil }
        do {
            guard try await store.saveEdit(snapshot, isNew: !persisted) else {
                saveState = L("原记录已被删除，请复制内容后另建备忘。")
                return false
            }
            persisted = true
            if generation == version { record.modifiedAt = snapshot.modifiedAt; saveState = L("已保存到本机"); dirty = false }
            await onSave()
            return true
        } catch { saveState = L("保存失败：") + error.localizedDescription; return false }
    }
    public func assign(_ id: UUID?) { record.categoryID = id; record.assignment = .manual; changed() }

    /// Used after an explicit history clear; closing the window must not schedule another save.
    public func discardChanges() {
        discarded = true; dirty = false; generation += 1
        pendingSave?.cancel(); pendingSave = nil
    }
}

