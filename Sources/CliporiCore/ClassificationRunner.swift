import Foundation

/// A serial queue of explicitly selected records. Never discovers work by scanning history.
@MainActor
public final class ClassificationRunner {
    private let store: MemoryStore
    private var task: Task<Void, Never>?
    private var queue: [UUID] = []
    private var queuedIDs: Set<UUID> = []
    private var runID = UUID()
    public init(store: MemoryStore) { self.store = store }
    public func stop() {
        runID = UUID(); task?.cancel(); task = nil
        queue.removeAll(); queuedIDs.removeAll()
    }
    public func start(ids: [UUID], client: AIClient,
                      onApply: @escaping @MainActor (Memory) -> Void,
                      onProcessed: @escaping @MainActor (UUID) -> Void = { _ in },
                      onError: @escaping @MainActor (Error) -> Void) {
        queue += ids.filter { queuedIDs.insert($0).inserted }
        guard task == nil, !queue.isEmpty else { return }
        let id = UUID(); runID = id
        task = Task {
            defer { if runID == id { task = nil; queue.removeAll(); queuedIDs.removeAll() } }
            do {
                var index = 0
                while !Task.isCancelled, index < queue.count {
                    let recordID = queue[index]; index += 1
                    if let record = try await store.record(id: recordID), record.canClassify {
                        let categories = try await store.categories().filter { !$0.isPinboard }
                        try Task.checkCancellation()
                        if !categories.isEmpty {
                            let categoryID = try await client.classify(record, categories: categories)
                            try Task.checkCancellation()
                            if try await store.applyClassification(id: record.id, categoryID: categoryID, expectedModifiedAt: record.modifiedAt),
                               let latest = try await store.record(id: record.id) { onApply(latest) }
                        }
                    }
                    try Task.checkCancellation()
                    queuedIDs.remove(recordID)
                    onProcessed(recordID)
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch is CancellationError {} catch { if !Task.isCancelled { onError(error) } }
        }
    }
}
