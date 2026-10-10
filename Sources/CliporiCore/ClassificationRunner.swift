import Foundation

/// One serial, cancellable queue per device. Rechecking the generation closes the empty-queue race.
@MainActor
public final class ClassificationRunner {
    private let store: MemoryStore
    private var task: Task<Void, Never>?
    private var generation = 0
    private var runID = UUID()
    public init(store: MemoryStore) { self.store = store }
    public func stop() { runID = UUID(); task?.cancel(); task = nil }
    public func start(client: AIClient, onApply: @escaping @MainActor (Memory) -> Void,
                      onError: @escaping @MainActor (Error) -> Void) {
        generation += 1
        guard task == nil else { return }
        let id = UUID(); runID = id
        task = Task {
            defer { if runID == id { task = nil } }
            do {
                while !Task.isCancelled {
                    let version = generation
                    guard let record = try await store.pendingClassification(limit: 1).first else {
                        if generation != version { continue }
                        break
                    }
                    let categories = try await store.categories().filter { !$0.isPinboard }
                    let categoryID = try await client.classify(record, categories: categories)
                    try Task.checkCancellation()
                    if try await store.applyClassification(id: record.id, categoryID: categoryID, expectedModifiedAt: record.modifiedAt),
                       let latest = try await store.record(id: record.id) { onApply(latest) }
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch is CancellationError {} catch { if !Task.isCancelled { onError(error) } }
        }
    }
}
