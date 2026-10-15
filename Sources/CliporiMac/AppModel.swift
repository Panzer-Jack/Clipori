import AppKit
import Combine
import CliporiCore

@MainActor
final class AppModel: ObservableObject {
    enum ShelfFocus { case search, cards }
    @Published var shelfFocus = ShelfFocus.search
    @Published var memories: [Memory] = []
    @Published var categories: [MemoryCategory] = []
    @Published private(set) var reorderingCategories = false
    @Published var preferences = Preferences()
    @Published var query = "" { didSet { if oldValue != query { scheduleSearch() } } }
    @Published var categoryID: UUID? { didSet { if oldValue != categoryID { scheduleSearch() } } }
    @Published private(set) var selectionID: UUID?
    @Published private(set) var selectionIDs: Set<UUID> = []
    @Published private(set) var memoryDrag: MemoryDrag?
    private var selectionAnchor: UUID?
    @Published private(set) var selectionToReveal: UUID?
    @Published var isVisible = false
    @Published var isSearchingAI = false
    @Published var aiResults: [Memory]?
    @Published var aiAnswer = ""
    @Published var totalCount = 0
    @Published var pendingIncoming = 0
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published var ready = false
    @Published var captureCount = 0
    @Published var hasAccessibilityPermission = false
    @Published private(set) var unclassifiedCount = 0
    @Published private(set) var isClassifyingHistory = false
    @Published private(set) var classificationCompleted = 0
    @Published private(set) var classificationTotal = 0
    @Published private(set) var classificationStatus = ""
    private var manualClassificationIDs: Set<UUID> = []
    private var classificationBatchID = UUID()
    private let classificationClientProvider: (() throws -> AIClient)?
    @Published var presentation = UUID()
    @Published var hasMore = false
    @Published private(set) var isClearingHistory = false

    let store: MemoryStore
    let dataDirectory: URL
    let demo: Bool
    lazy var cloudSync = CloudSyncController(store: store, directory: dataDirectory)
    var onPaste: ((Memory) -> Void)?
    var onCopy: ((Memory) -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onPreview: ((Memory) -> Void)?
    var onRename: ((Memory) -> Void)?
    var onValidateShortcuts: ((ShortcutPreferences) throws -> Void)?
    var onPreferencesChanged: (() -> Void)?
    var onShortcutRecording: ((Bool) -> Void)?
    var recordingShortcut = false
    var requestedSettingsTab = 0
    var requestNewPinboard = false
    private var deletedRecords: [Memory] = []
    private var restoringRecords: [Memory] = []
    private var retainedAttachments: Set<String> { Set((deletedRecords + restoringRecords).compactMap(\.attachment)) }
    var onEdit: ((Memory?) -> Void)?
    var onSettings: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onSticky: ((Memory) -> Void)?
    var onDailyNotes: ((Memory?) -> Void)?
    var onPrepareHistoryClear: (() async -> Bool)?
    var onHistoryCleared: (() -> Void)?
    private var searchTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private lazy var classifier = ClassificationRunner(store: store)
    private var noticeTask: Task<Void, Never>?
    private var loadingMore = false
    private var generation = 0
    private var historyRevision = 0
    private var cleanupTimer: Timer?
    private var shelfOrderBeforeUse: [UUID]?
    private var recentlyUsedIDs: [UUID] = []

    var displayed: [Memory] { aiResults ?? memories }
    var selected: Memory? { displayed.first { $0.id == selectionID } }
    var motion: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var keychainService: String { demo ? "app.clipori.preview" : "app.clipori" }

    init(directory: URL? = nil, preview: Bool? = nil, classificationClientProvider: (() throws -> AIClient)? = nil) throws {
        self.classificationClientProvider = classificationClientProvider
        demo = preview ?? ProcessInfo.processInfo.arguments.contains("--demo")
        let override = ProcessInfo.processInfo.environment["CLIPORI_DATA_DIR"]
        if let directory { dataDirectory = directory }
        else if let override { dataDirectory = URL(fileURLWithPath: override, isDirectory: true) }
        else if demo { dataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Clipori-Preview", isDirectory: true) }
        else { dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clipori", isDirectory: true) }
        store = try MemoryStore(url: dataDirectory.appendingPathComponent("clipori.sqlite"))
    }

    func start() async {
        do {
            preferences = try await store.preferences()
            L10n.language = preferences.language
            categories = try await store.categories()
            if demo {
                if try await store.count() == 0 { try await seedPreview() }
            }
            try await store.clean(retentionDays: preferences.retentionDays)
            try await store.pruneImages()
            await reload(); ready = true
            applyAppearance()
            cloudSync.onReceive = { [weak self] in
                guard let self else { return }
                self.cancelAI()
                self.categories = (try? await self.store.categories()) ?? self.categories
                if self.isVisible {
                    var current: [Memory] = []
                    for memory in self.memories {
                        if let latest = try? await self.store.record(id: memory.id) { current.append(latest) }
                    }
                    self.memories = current
                    self.reconcileSelection()
                    self.pendingIncoming += 1
                } else { await self.reload() }
            }
            if !demo { await cloudSync.setEnabled(preferences.iCloudEnabled) }
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.cleanExpired() }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() async {
        let currentGeneration = generation
        do {
            let records = try await store.list(query: query, categoryID: categoryID)
            let count = try await store.count()
            guard currentGeneration == generation else { return }
            memories = records
            if isVisible, let order = shelfOrderBeforeUse {
                let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
                let known = records.filter { ranks[$0.id] != nil }.sorted { ranks[$0.id]! < ranks[$1.id]! }
                memories = records.filter { ranks[$0.id] == nil } + known
                shelfOrderBeforeUse = memories.map(\.id)
            }
            totalCount = count; hasMore = records.count == 80
            reconcileSelection()
        } catch { errorMessage = error.localizedDescription }
    }
    func loadMore() async {
        guard hasMore && !loadingMore && aiResults == nil else { return }
        loadingMore = true; defer { loadingMore = false }
        let currentGeneration = generation
        do {
            let next = try await store.list(query: query, categoryID: categoryID, offset: memories.count)
            guard currentGeneration == generation else { return }
            let existing = Set(memories.map(\.id))
            memories += next.filter { !existing.contains($0.id) }; hasMore = next.count == 80
        } catch { errorMessage = error.localizedDescription }
    }
    private func scheduleSearch() {
        generation += 1; searchTask?.cancel(); cancelAI()
        select(nil, reveal: false)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }
    @discardableResult
    func accept(_ record: Memory) async -> Memory? {
        guard !isClearingHistory else { return nil }
        let revision = historyRevision
        do {
            let captured = try await store.captureText(record)
            guard revision == historyRevision else { return nil }
            if captured.id == record.id { try await didCapture(); classifyNewRecord(captured) }
            else {
                captureCount += 1
                await didUse(captured, deferWhileVisible: false)
            }
            return captured
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func didUse(_ record: Memory, deferWhileVisible: Bool = true) async {
        guard preferences.moveToFrontAfterUse, !isClearingHistory else { return }
        let revision = historyRevision
        if deferWhileVisible, isVisible, shelfOrderBeforeUse == nil {
            shelfOrderBeforeUse = memories.map(\.id)
        }
        do {
            let updated = try await store.markUsed(id: record.id)
            guard updated, revision == historyRevision else { return }
            recentlyUsedIDs.removeAll { $0 == record.id }
            recentlyUsedIDs.insert(record.id, at: 0)
            if !deferWhileVisible {
                // An external duplicate is a new capture, while earlier card clicks remain deferred.
                if shelfOrderBeforeUse != nil {
                    shelfOrderBeforeUse?.removeAll { $0 == record.id }
                    shelfOrderBeforeUse?.insert(record.id, at: 0)
                }
                await reload()
            } else if !isVisible { await reload() }
        } catch { errorMessage = error.localizedDescription }
    }
    func refreshForPresentation() async {
        shelfOrderBeforeUse = nil
        let usedIDs = recentlyUsedIDs
        recentlyUsedIDs = []
        pendingIncoming = 0
        await reload()
        for id in usedIDs.reversed() {
            if let index = aiResults?.firstIndex(where: { $0.id == id }),
               let used = aiResults?.remove(at: index) { aiResults?.insert(used, at: 0) }
        }
        if let id = usedIDs.first, displayed.contains(where: { $0.id == id }) { select(id) }
    }
    @discardableResult
    func acceptImage(_ data: Data, record: Memory) async -> Memory? {
        guard !isClearingHistory else { return nil }
        let revision = historyRevision
        do {
            let image = try await ClipboardImageProcessor.shared.prepare(data)
            guard !isClearingHistory, revision == historyRevision else { return nil }
            let captured = try await store.saveImage(record, png: image.png, thumbnail: image.thumbnail, size: image.size)
            guard revision == historyRevision else { return nil }
            try await didCapture()
            classifyNewRecord(captured)
            return captured
        } catch { toast(error.localizedDescription); return nil }
    }
    private func didCapture() async throws {
        captureCount += 1
        totalCount = try await store.count()
        // Newly cut/copied content must be available even if capture finishes after the shelf opens.
        await reload()
    }
    func showIncoming() { pendingIncoming = 0; query = ""; categoryID = nil; cancelAI(); Task { await reload() } }

    func save(_ record: Memory) async throws {
        try await store.save(record)
        // Invalidate stale AI answers as soon as the underlying content changes.
        cancelAI(); await reload()
    }
    func delete(_ record: Memory) {
        guard !isClearingHistory else { return }
        let revision = historyRevision
        Task {
            do {
                guard let latest = try await store.record(id: record.id) else { return }
                try await store.delete(id: record.id)
                guard revision == historyRevision else { return }
                deletedRecords.append(latest); if deletedRecords.count > 20 { deletedRecords.removeFirst() }
                try await store.pruneImages(keeping: retainedAttachments)
                cancelAI(); await reload(); toast(L("记录已删除，可撤销"))
            }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func toggleProtected(_ record: Memory) {
        Task {
            do {
                guard var latest = try await store.record(id: record.id) else { return }
                latest.keepForever.toggle(); latest.modifiedAt = Date()
                try await save(latest)
                toast(latest.keepForever ? L("已设为永久保留的例外") : L("已恢复全局保留规则"))
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func assign(_ record: Memory, to category: UUID?) {
        let ids = selectionIDs.contains(record.id) ? displayed.filter { selectionIDs.contains($0.id) }.map(\.id) : [record.id]
        Task { await assign(ids: ids, to: category) }
    }
    func assign(ids: [UUID], to category: UUID?) async {
        do {
            let updated = try await store.assign(ids: ids, to: category)
            cancelAI()
            let replacements = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
            memories = memories.compactMap { record in
                let latest = replacements[record.id] ?? record
                return categoryID == nil || latest.categoryID == categoryID ? latest : nil
            }
            reconcileSelection()
            // Keep all loaded pages and the horizontal scroll position when moving in All memories.
            if categoryID != nil, memories.count < 80 { await reload() }
            toast(updated.isEmpty ? L("选中的记录已不存在。") : LF("已将 %d 条记忆移到%@", updated.count, categories.first { $0.id == category }?.displayName ?? L("未分类")))
        } catch { errorMessage = error.localizedDescription }
    }
    func beginDragging(_ id: UUID) -> MemoryDrag? {
        guard let record = displayed.first(where: { $0.id == id }) else { return nil }
        if !selectionIDs.contains(id) { select(id, reveal: false) }
        let drag = MemoryDrag(ids: displayed.filter { selectionIDs.contains($0.id) }.map(\.id), title: record.displayTitle)
        memoryDrag = drag
        return drag
    }
    func endDragging() { memoryDrag = nil }
    func dropMemories(to category: UUID) -> Bool {
        guard let drag = memoryDrag, categories.contains(where: { $0.id == category }) else { return false }
        endDragging()
        Task { await assign(ids: drag.ids, to: category) }
        return true
    }
    func editSelected() { onEdit?(selected) }
    func select(_ id: UUID?, reveal: Bool = true) {
        selectionID = id
        selectionIDs = Set(id.map { [$0] } ?? [])
        selectionAnchor = id
        selectionToReveal = reveal ? id : nil
    }
    func selectFromPointer(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        shelfFocus = .cards; selectionToReveal = nil
        if modifiers.contains(.shift),
           let anchor = displayed.firstIndex(where: { $0.id == (selectionAnchor ?? selectionID) }),
           let end = displayed.firstIndex(where: { $0.id == id }) {
            let range = Set(displayed[min(anchor, end)...max(anchor, end)].map(\.id))
            selectionIDs = modifiers.contains(.command) ? selectionIDs.union(range) : range
            selectionID = id
        } else if modifiers.contains(.command) {
            if selectionIDs.contains(id) {
                selectionIDs.remove(id)
                if selectionID == id { selectionID = displayed.first { selectionIDs.contains($0.id) }?.id }
            } else { selectionIDs.insert(id); selectionID = id }
            selectionAnchor = selectionID
        } else if !selectionIDs.contains(id) || selectionIDs.count <= 1 {
            select(id, reveal: false)
        }
        // A press inside a group preserves it for dragging; a plain release collapses it.
    }
    func clickCard(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
        guard modifiers.intersection([.command, .shift]).isEmpty,
              let record = displayed.first(where: { $0.id == id }) else { return }
        shelfFocus = .cards
        select(id, reveal: false)
        copy(record)
    }
    private func reconcileSelection() {
        let visibleIDs = Set(displayed.map(\.id))
        selectionIDs.formIntersection(visibleIDs)
        if selectionIDs.isEmpty { select(displayed.first?.id, reveal: false); return }
        if selectionID.map({ !selectionIDs.contains($0) }) ?? true {
            selectionID = displayed.first { selectionIDs.contains($0.id) }?.id
        }
        if selectionAnchor.map({ !visibleIDs.contains($0) }) ?? true { selectionAnchor = selectionID }
    }
    func moveSelection(_ delta: Int) {
        guard !displayed.isEmpty else { return }
        let current = displayed.firstIndex { $0.id == selectionID } ?? (delta > 0 ? -1 : displayed.count)
        select(displayed[min(max(current + delta, 0), displayed.count - 1)].id)
    }
    func paste(_ record: Memory, plainText: Bool = false) {
        if plainText && record.kind == .image { toast(L("图片不支持纯文本粘贴，请使用普通粘贴。")); return }
        onPaste?(record)
    }
    func pasteSelected(plainText: Bool = false) { if let selected { paste(selected, plainText: plainText) } }
    func copy(_ record: Memory) { onCopy?(record) }
    func undoDeletion() {
        guard !isClearingHistory else { return }
        let revision = historyRevision
        guard var record = deletedRecords.popLast() else { return }
        let original = record
        restoringRecords.append(original)
        // Deleted IDs remain terminal for synchronization; explicit undo creates a new identity.
        record.id = UUID(); record.modifiedAt = Date()
        Task {
            defer { restoringRecords.removeAll { $0.id == original.id } }
            guard revision == historyRevision else { return }
            do { try await save(record); if revision == historyRevision { toast(L("已恢复记录")) } }
            catch { if revision == historyRevision { deletedRecords.append(original); errorMessage = error.localizedDescription } }
        }
    }

    @discardableResult
    func clearHistory() async throws -> Int {
        guard !isClearingHistory else { return 0 }
        isClearingHistory = true; historyRevision += 1
        generation += 1; searchTask?.cancel(); cancelAI(); stopClassification()
        defer { isClearingHistory = false }
        // Finish pending autosaves before the transaction, including a new note's first save.
        if let prepare = onPrepareHistoryClear, !(await prepare()) { throw HistoryClearError.unsavedNote }
        let count = try await store.deleteAllMemories()
        query = ""; categoryID = nil
        generation += 1; searchTask?.cancel(); cancelAI()
        deletedRecords.removeAll(); restoringRecords.removeAll()
        memories = []; select(nil); endDragging()
        shelfOrderBeforeUse = nil; recentlyUsedIDs = []
        pendingIncoming = 0; totalCount = 0; hasMore = false
        noticeTask?.cancel(); notice = nil; errorMessage = nil
        onHistoryCleared?()
        await ClipboardImageProcessor.shared.clearCache()
        await reload()
        return count
    }
    func moveCategory(_ delta: Int) {
        let ids: [UUID?] = [nil] + categories.map { Optional($0.id) }
        let index = ids.firstIndex(of: categoryID) ?? 0
        categoryID = ids[(index + delta + ids.count) % ids.count]
    }
    func toggleCapture() {
        var value = preferences; value.capturePaused.toggle()
        Task { do { try await updatePreferences(value) } catch { errorMessage = error.localizedDescription } }
    }

    func makeAIClient() throws -> AIClient {
        try AIClient(configuration: preferences.ai, apiKey: Keychain.read(service: keychainService))
    }
    func runAISearch() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { toast(L("输入你想找回的内容，再点击 AI 找回。")); return }
        aiTask?.cancel()
        guard preferences.ai.isConfigured else { onSettings?(); return }
        let token = UUID(); activeSearch = token
        isSearchingAI = true; aiResults = nil; aiAnswer = ""
        aiTask = Task {
            defer { if activeSearch == token { isSearchingAI = false } }
            do {
                let client = try makeAIClient()
                let result = try await client.search(question, store: store, categoryID: categoryID)
                guard !Task.isCancelled, activeSearch == token else { return }
                aiResults = result.records; aiAnswer = result.answer; select(result.records.first?.id)
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
    private var activeSearch: UUID?
    func cancelAI() { activeSearch = nil; aiTask?.cancel(); aiTask = nil; isSearchingAI = false; aiResults = nil; aiAnswer = "" }

    func updatePreferences(_ value: Preferences) async throws {
        try value.shortcuts.validate()
        try onValidateShortcuts?(value.shortcuts)
        do { try await store.savePreferences(value) }
        catch { try? onValidateShortcuts?(preferences.shortcuts); throw error }
        L10n.language = value.language
        preferences = value; applyAppearance(); onPreferencesChanged?()
        stopClassification()
        await cleanExpired()
        if !demo { await cloudSync.setEnabled(value.iCloudEnabled) }
    }
    func refreshCategories() async {
        do { categories = try await store.categories(); if let categoryID, !categories.contains(where: { $0.id == categoryID }) { self.categoryID = nil }; cancelAI(); await reload() }
        catch { errorMessage = error.localizedDescription }
    }
    func reorderCategories(_ ordered: [MemoryCategory]) async throws {
        guard !reorderingCategories else { return }
        reorderingCategories = true
        defer { reorderingCategories = false }
        let previous = categories
        categories = ordered
        do { categories = try await store.reorderCategories(ordered.map(\.id)) }
        catch {
            categories = (try? await store.categories()) ?? previous
            throw error
        }
    }
    func cleanExpired() async {
        do {
            if try await store.clean(retentionDays: preferences.retentionDays) > 0 { cancelAI(); await reload() }
            try await store.pruneImages(keeping: retainedAttachments)
        } catch { errorMessage = error.localizedDescription }
    }
    private func classifyNewRecord(_ record: Memory) {
        guard preferences.ai.autoClassify, preferences.ai.isConfigured, !demo,
              !isClearingHistory, record.assignment == .none, record.canClassify else { return }
        do { enqueueClassification(ids: [record.id], client: try classificationClientProvider?() ?? makeAIClient()) }
        catch { toast(error.localizedDescription) }
    }
    func refreshUnclassifiedCount() async {
        do { unclassifiedCount = try await store.unclassifiedCount() }
        catch { errorMessage = error.localizedDescription }
    }
    func classifyUnclassifiedRecords() async {
        guard !isClassifyingHistory, !isClearingHistory, !demo else { return }
        isClassifyingHistory = true
        classificationStatus = ""
        classificationCompleted = 0; classificationTotal = 0
        let batchID = UUID(); classificationBatchID = batchID
        do {
            let client = try classificationClientProvider?() ?? makeAIClient()
            let ids = try await store.unclassifiedRecordIDs()
            guard classificationBatchID == batchID, !isClearingHistory else { return }
            classificationTotal = ids.count; unclassifiedCount = ids.count
            guard !ids.isEmpty else { isClassifyingHistory = false; return }
            manualClassificationIDs = Set(ids)
            enqueueClassification(ids: ids, client: client)
        } catch {
            guard classificationBatchID == batchID else { return }
            isClassifyingHistory = false; classificationStatus = error.localizedDescription
        }
    }
    func stopClassification() {
        if isClassifyingHistory { classificationStatus = L("已停止，已完成的分类已保留。") }
        classifier.stop(); classificationBatchID = UUID()
        manualClassificationIDs.removeAll(); isClassifyingHistory = false
    }
    private func enqueueClassification(ids: [UUID], client: AIClient) {
        classifier.start(ids: ids, client: client, onApply: { [weak self] record in
            guard let self else { return }
            if let index = self.memories.firstIndex(where: { $0.id == record.id }) { self.memories[index] = record }
        }, onProcessed: { [weak self] id in
            guard let self else { return }
            if self.manualClassificationIDs.remove(id) != nil {
                self.classificationCompleted += 1
                if self.manualClassificationIDs.isEmpty {
                    self.isClassifyingHistory = false
                    self.classificationStatus = LF("本次已处理 %d 条，未匹配的记录保留在未分类。", self.classificationCompleted)
                }
            }
            Task { await self.refreshUnclassifiedCount() }
        }, onError: { [weak self] error in
            guard let self else { return }
            self.manualClassificationIDs.removeAll(); self.isClassifyingHistory = false
            self.classificationStatus = L("分类暂未完成，可手动重试：") + error.localizedDescription
            self.toast(self.classificationStatus)
        })
    }
    func toast(_ text: String) {
        noticeTask?.cancel(); notice = text
        noticeTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { notice = nil } }
    }
    func applyAppearance() {
        NSApp.appearance = preferences.appearance == "dark" ? NSAppearance(named: .darkAqua) : preferences.appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    private func seedPreview() async throws {
        let samples: [(String, String, Int, String)] = [
            (L("把灵感，留在手边。"), L("那些一闪而过的想法，\n值得被温柔地记住。\n\n复制即备忘，想起时就来找我。"), 4, "Clipori"),
            (L("周末的散步地图"), L("去河边看看日落，\n路过那家有猫的咖啡店。\n\n记得带相机，还有好心情。"), 2, L("备忘录")),
            ("Spring, a little softer", "withAnimation(.spring(\n    response: 0.38,\n    dampingFraction: 0.86\n)) {\n    isPresented.toggle()\n}", 3, "Xcode"),
            (L("让好设计成为日常"), L("https://developer.apple.com/design/\n\n自然的反馈、清晰的层次，\n还有每一次恰到好处的过渡。"), 1, "Safari"),
            (L("下一次的小小计划"), L("整理桌面\n读完那本没看完的书\n做一个轻巧、丝滑的小应用 ✧"), 0, L("手动记录")),
            (L("关于星星的片段"), L("等风来，也等新的灵感。\n\n「日々の小さなきらめき」"), 4, L("手动记录"))
        ]
        for (index, sample) in samples.enumerated() {
            var record = Memory(title: sample.0, body: sample.1, source: sample.3, now: Date().addingTimeInterval(-Double(index * 420)))
            record.categoryID = MemoryCategory.defaults[sample.2].id; record.assignment = .manual
            try await store.save(record)
        }
    }
}

private enum HistoryClearError: LocalizedError {
    case unsavedNote
    var errorDescription: String? { L("有备忘未能保存，请处理后再清空记录。") }
}
