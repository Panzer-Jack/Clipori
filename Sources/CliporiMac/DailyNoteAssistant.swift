import Foundation
import Combine
import CliporiCore

@MainActor
final class DailyNoteAssistant: ObservableObject {
    typealias Generate = @MainActor (DailyClipboardContext, DailyNote) async throws -> [DailyNoteSuggestion]
    @Published var isPresented = false
    @Published var suggestions: [DailyNoteSuggestion] = []
    @Published var selected: Set<UUID> = []
    @Published private(set) var day = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var sourceCount = 0
    @Published private(set) var totalRecords = 0
    @Published private(set) var isTruncated = false
    @Published private(set) var message: String?
    @Published private(set) var needsConfiguration = false
    @Published private(set) var hasFailed = false
    @Published private(set) var startedAt: Date?
    private let store: MemoryStore
    private let generate: Generate
    private var request: Task<Void, Never>?
    private var runID = UUID()

    init(store: MemoryStore, generate: @escaping Generate) { self.store = store; self.generate = generate }

    func start(for note: DailyNote) {
        cancel()
        let token = UUID(); runID = token
        day = note.day; isPresented = true; isGenerating = true
        suggestions = []; selected = []; message = nil; needsConfiguration = false; hasFailed = false; startedAt = Date()
        sourceCount = 0; totalRecords = 0; isTruncated = false
        request = Task { [self] in
            defer { if runID == token { isGenerating = false; request = nil } }
            do {
                let context = try await store.dailyClipboard(on: note.day)
                guard runID == token, !Task.isCancelled else { return }
                sourceCount = context.sources.count; totalRecords = context.totalRecords; isTruncated = context.isTruncated
                guard !context.sources.isEmpty else { message = L("这一天没有可整理的文字或链接剪贴板记录。可以先手动添加事项。"); return }
                let proposed = try await generate(context, note)
                guard runID == token, !Task.isCancelled else { return }
                let validIDs = try await store.unchangedDailySourceIDs(context)
                guard runID == token, !Task.isCancelled else { return }
                suggestions = proposed.compactMap { $0.retainingSources(validIDs) }
                selected = Set(suggestions.map(\.id))
                if suggestions.isEmpty { message = L("没有发现新的可靠事项，已有内容已保留。") }
            } catch is CancellationError {} catch {
                guard runID == token, !Task.isCancelled else { return }
                if case AIError.configuration = error { needsConfiguration = true }
                hasFailed = true
                if (error as? URLError)?.code == .timedOut {
                    message = LF("AI 服务在 %d 秒内未完成整理，可能是记录较多或服务响应较慢。备忘录未改动；可以重试，或在设置中更换模型。", Int(AIClient.dailyNoteTimeout))
                } else if error as? AIError == .service(504) || error as? AIError == .service(408) {
                    message = L("AI 服务网关超时。备忘录未改动；请稍后重试，或检查服务端超时设置。")
                } else {
                    message = error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        runID = UUID(); request?.cancel(); request = nil
        if isGenerating { message = L("整理已停止。") }
        isGenerating = false
    }

    func dismiss() { cancel(); isPresented = false }

    @discardableResult
    func apply(to model: DailyNotesModel) -> Bool {
        guard !isGenerating else { return false }
        let chosen = suggestions.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return false }
        guard let count = model.applySuggestions(chosen, on: day) else {
            message = L("日期已切换，请在目标日期重新整理。"); return false
        }
        if count == 0 { message = L("这些事项已在备忘录中，无需重复加入。"); return false }
        dismiss(); return true
    }
}
