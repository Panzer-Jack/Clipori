import SwiftUI
import CliporiCore

struct DailyNoteAISheet: View {
    @ObservedObject var assistant: DailyNoteAssistant
    @ObservedObject var model: DailyNotesModel
    let configureAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Color.clipori)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("AI 辅助整理")).font(.system(size: 19, weight: .semibold))
                    Text(assistant.day).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { assistant.dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help(L("关闭")).accessibilityLabel(L("关闭"))
            }.padding(24)
            VStack(alignment: .leading, spacing: 7) {
                Text(L("基于这一天的剪贴板和已有事项整理，选中后加入；也可以先修改建议。"))
                Text(L("文字片段与已有事项会发送至你在设置中配置的 AI 服务，图片不会发送。"))
                    .foregroundStyle(.secondary)
                if assistant.totalRecords > 0 {
                    Text(LF("当日 %d 条文字记录 · 去重后本次参考 %d 条片段", assistant.totalRecords, assistant.sourceCount))
                        .foregroundStyle(.secondary)
                }
                if assistant.isTruncated {
                    Text(L("记录较多或较长，本次按最新记录优先截取；未覆盖的内容可手动补充。"))
                        .foregroundStyle(.secondary)
                }
            }.font(.system(size: 12)).padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            if assistant.isGenerating {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(L("正在梳理事项、合并重复内容…")).font(.system(size: 13)).foregroundStyle(.secondary)
                    Button(L("停止整理")) { assistant.cancel() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assistant.suggestions.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: assistant.needsConfiguration ? "slider.horizontal.3" : "text.magnifyingglass")
                        .font(.system(size: 30)).foregroundStyle(Color.clipori)
                    Text(assistant.message ?? L("没有发现新的可靠事项，已有内容已保留。"))
                        .font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if assistant.needsConfiguration { Button(L("配置 AI"), action: configureAI) }
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach($assistant.suggestions) { $suggestion in
                            suggestionCard($suggestion)
                        }
                    }.padding(22)
                }
                if let message = assistant.message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 10) }
            }
            Divider()
            HStack(spacing: 12) {
                Button(L("重新整理")) { if let note = model.note { assistant.start(for: note) } }
                    .disabled(assistant.isGenerating || model.isLoading)
                Spacer()
                Button(L("取消")) { assistant.dismiss() }.keyboardShortcut(.cancelAction)
                Button(LF("加入所选（%d）", assistant.selected.count)) { assistant.apply(to: model) }
                    .buttonStyle(.borderedProminent).tint(.clipori)
                    .disabled(assistant.isGenerating || assistant.selected.isEmpty || model.isLoading)
                    .accessibilityIdentifier("daily-ai-apply")
            }.padding(20)
        }.frame(width: 660, height: 650).background(.background)
    }

    private func suggestionCard(_ binding: Binding<DailyNoteSuggestion>) -> some View {
        let suggestion = binding.wrappedValue
        let target = model.note?.items.first { $0.id == suggestion.targetItemID }
        return HStack(alignment: .top, spacing: 12) {
            Toggle(L("选择这条建议"), isOn: Binding(get: { assistant.selected.contains(suggestion.id) }, set: { value in
                if value { assistant.selected.insert(suggestion.id) } else { assistant.selected.remove(suggestion.id) }
            })).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 10) {
                if let target {
                    Text(LF("补充到：%@", target.title)).font(.system(size: 14, weight: .semibold))
                } else {
                    TextField(L("事项名称"), text: binding.title, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                    TextField(L("备注或链接（可选）"), text: binding.note, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(binding.tasks) { task in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "square").foregroundStyle(.tertiary)
                        TextField(L("写下一个子任务"), text: task.title, axis: .vertical).textFieldStyle(.plain).font(.system(size: 13))
                    }
                }
                DailyNoteEvidenceView(evidence: suggestion.evidence + suggestion.tasks.flatMap { $0.evidence ?? [] })
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16)
            .background(Color.clipori.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct DailyNoteEvidenceView: View {
    let evidence: [DailyNoteEvidence]
    private var unique: [DailyNoteEvidence] {
        var seen: Set<DailyNoteEvidence> = []
        return evidence.filter { seen.insert($0).inserted }
    }
    var body: some View {
        if !unique.isEmpty {
            DisclosureGroup(LF("剪贴板来源（%d）", unique.count)) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(unique, id: \.self) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.app).fontWeight(.medium)
                            Text(source.quote).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 6)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
