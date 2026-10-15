import SwiftUI
import CliporiCore

@MainActor
final class MobileModel: ObservableObject {
    @Published var records: [Memory] = []
    @Published var categories: [MemoryCategory] = []
    @Published var preferences = Preferences()
    @Published var query = "" { didSet { if oldValue != query { search() } } }
    @Published var categoryID: UUID? { didSet { if oldValue != categoryID { search() } } }
    @Published var aiAnswer = ""
    @Published var searchingAI = false
    @Published var error: String?
    @Published var hasMore = false
    @Published var loading = true
    @Published private(set) var isClassifyingHistory = false
    @Published private(set) var classificationCompleted = 0
    @Published private(set) var classificationTotal = 0
    private var manualClassificationIDs: Set<UUID> = []
    private var classificationBatchID = UUID()
    let store: MemoryStore
    let cloud: CloudSyncController
    private let classifier: ClassificationRunner
    private var task: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var generation = 0
    private var showingAI = false
    private var loadingMore = false
    private var started = false

    init() throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clipori")
        store = try MemoryStore(url: directory.appendingPathComponent("clipori.sqlite"))
        cloud = CloudSyncController(store: store, directory: directory)
        classifier = ClassificationRunner(store: store)
    }
    func start() async {
        guard !started else { return }; started = true
        do {
            preferences = try await store.preferences()
            L10n.language = preferences.language
            try await store.clean(retentionDays: preferences.retentionDays)
            categories = try await store.categories()
            cloud.onReceive = { [weak self] in await self?.refresh() }
            await reload(); loading = false
            await cloud.setEnabled(preferences.iCloudEnabled)
        } catch { self.error = error.localizedDescription; loading = false }
    }
    func refresh() async {
        do { categories = try await store.categories(); try await store.clean(retentionDays: preferences.retentionDays) }
        catch { self.error = error.localizedDescription }
        cancelAI(); await reload()
    }
    func reload() async {
        let version = generation
        do {
            let result = try await store.list(query: query, categoryID: categoryID)
            guard version == generation else { return }
            records = result; hasMore = result.count == 80
        } catch { self.error = error.localizedDescription }
    }
    func loadMore() async {
        guard hasMore, !showingAI, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        let version = generation
        do {
            let more = try await store.list(query: query, categoryID: categoryID, offset: records.count)
            guard version == generation else { return }
            let ids = Set(records.map(\.id)); records += more.filter { !ids.contains($0.id) }; hasMore = more.count == 80
        } catch { self.error = error.localizedDescription }
    }
    private func search() {
        generation += 1; task?.cancel(); cancelAI()
        task = Task { try? await Task.sleep(for: .milliseconds(120)); if !Task.isCancelled { await reload() } }
    }
    private func cancelAI() { aiTask?.cancel(); aiTask = nil; searchingAI = false; showingAI = false; aiAnswer = "" }
    func aiSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        task?.cancel(); generation += 1; cancelAI(); searchingAI = true
        let version = generation
        aiTask = Task {
            defer { if version == generation { searchingAI = false } }
            do {
                let result = try await client().search(query, store: store, categoryID: categoryID)
                guard !Task.isCancelled, version == generation else { return }
                records = result.records; aiAnswer = result.answer; showingAI = true; hasMore = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func client() throws -> AIClient { try AIClient(configuration: preferences.ai, apiKey: Keychain.read(service: "app.clipori")) }
    func capture(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let record = Memory(body: text, source: L("iPhone 剪贴板"))
            try await store.save(record); await refresh()
            if preferences.ai.autoClassify, preferences.ai.isConfigured {
                enqueueClassification(ids: [record.id], client: try client())
            }
        }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ record: Memory) async {
        do { try await store.delete(id: record.id); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func updatePreferences(_ value: Preferences, secret: String) async throws {
        try Keychain.save(secret.trimmingCharacters(in: .whitespacesAndNewlines), service: "app.clipori")
        try await store.savePreferences(value); L10n.language = value.language; preferences = value; stopClassification()
        await refresh(); await cloud.setEnabled(value.iCloudEnabled)
    }
    func classifyUnclassifiedRecords() async {
        guard !isClassifyingHistory else { return }
        isClassifyingHistory = true; classificationCompleted = 0; classificationTotal = 0
        let batchID = UUID(); classificationBatchID = batchID
        do {
            let client = try client()
            let ids = try await store.unclassifiedRecordIDs()
            guard batchID == classificationBatchID else { return }
            classificationTotal = ids.count; manualClassificationIDs = Set(ids)
            guard !ids.isEmpty else { isClassifyingHistory = false; return }
            enqueueClassification(ids: ids, client: client)
        } catch {
            guard batchID == classificationBatchID else { return }
            isClassifyingHistory = false; self.error = error.localizedDescription
        }
    }
    func stopClassification() {
        classifier.stop(); classificationBatchID = UUID()
        manualClassificationIDs.removeAll(); isClassifyingHistory = false
    }
    private func enqueueClassification(ids: [UUID], client: AIClient) {
        classifier.start(ids: ids, client: client, onApply: { [weak self] record in
            guard let self, let index = self.records.firstIndex(where: { $0.id == record.id }) else { return }
            self.records[index] = record
        }, onProcessed: { [weak self] id in
            guard let self, self.manualClassificationIDs.remove(id) != nil else { return }
            self.classificationCompleted += 1
            if self.manualClassificationIDs.isEmpty { self.isClassifyingHistory = false }
        }, onError: { [weak self] error in
            self?.manualClassificationIDs.removeAll(); self?.isClassifyingHistory = false
            self?.error = L("分类暂未完成，可手动重试：") + error.localizedDescription
        })
    }
}
