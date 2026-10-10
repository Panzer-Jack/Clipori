import SwiftUI
import CliporiCore

struct MobileSettings: View {
    @ObservedObject var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Preferences()
    @State private var secret = ""
    @State private var feedback = ""
    @State private var testing = false
    @State private var saving = false
    @State private var retention = 0
    @State private var confirmingRetention = false
    @State private var categoryName = ""
    @State private var categoryID: UUID?
    @State private var categoryColor = "lavender"
    @State private var categoryPinboard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) { MascotView(size: 48); VStack(alignment: .leading) { Text(L("让 Clipori 更懂你")).font(.headline); Text(L("一点小设置，刚刚好的记忆空间。")).font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 8)
                    Picker(L("外观"), selection: $draft.appearance) { Text(L("跟随系统")).tag("system"); Text(L("浅色")).tag("light"); Text(L("深色")).tag("dark") }
                    Picker(L("语言"), selection: $draft.language) { ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle(L("减少动效"), isOn: $draft.reduceMotion)
                }
                Section(L("你的 AI，你来选择")) {
                    Picker(L("接口格式"), selection: $draft.ai.format) { ForEach(AIFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .onChange(of: draft.ai.format) { old, new in if draft.ai.baseURL == old.defaultBaseURL { draft.ai.baseURL = new.defaultBaseURL } }
                    TextField("Base URL", text: $draft.ai.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField(L("模型名称"), text: $draft.ai.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(L("API Key · 仅保存在本机"), text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(testing ? L("正在测试…") : L("测试连接")) {
                        testing = true
                        let config = draft.ai; let key = secret
                        Task {
                            do { try await AIClient(configuration: config, apiKey: key).testConnection(); feedback = L("连接成功") }
                            catch { feedback = error.localizedDescription }
                            testing = false
                        }
                    }.disabled(testing)
                    Toggle(L("AI 自动分类"), isOn: $draft.ai.autoClassify)
                    Text(L("开启分类后会发送待分类内容至你配置的服务。AI 搜索发送问题和候选片段。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L("记多久，由你决定")) {
                    Picker(L("历史保留"), selection: $retention) {
                        ForEach(HistoryRetention.presets) { Text($0.title).tag($0.days) }
                        if !HistoryRetention.presets.contains(where: { $0.days == retention }) { Text(LF("%d 天（旧设置）", retention)).tag(retention) }
                    }
                    Text(L("默认保留 1 个月，按时间清理。固定记录和固定分类不受期限影响，编辑不会延长保留时间。")).font(.caption).foregroundStyle(.secondary)
                }
                Section("iCloud") { MobileCloudSettings(sync: model.cloud, enabled: $draft.iCloudEnabled) }
                Section(L("分类 · 修改立即保存")) {
                    ForEach(model.categories) { category in
                        HStack {
                            Image(systemName: "tag").foregroundStyle(Color.category(category.color))
                            Button(category.displayName) { categoryID = category.id; categoryName = category.name; categoryColor = category.color; categoryPinboard = category.isPinboard }.foregroundStyle(.primary)
                            if category.isPinboard { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                            Spacer()
                            Button(role: .destructive) { Task { do { try await model.store.deleteCategory(id: category.id); await model.refresh() } catch { feedback = error.localizedDescription } } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                    TextField(L("分类名称"), text: $categoryName)
                    Toggle(L("固定分类（Pinboard）"), isOn: $categoryPinboard)
                    Picker(L("颜色"), selection: $categoryColor) { Text(L("薰衣草")).tag("lavender"); Text(L("天空")).tag("blue"); Text(L("薄荷")).tag("mint"); Text(L("蜜桃")).tag("peach"); Text(L("樱花")).tag("pink") }
                    Button(categoryID == nil ? L("添加分类") : L("保存分类")) {
                        let category = MemoryCategory(id: categoryID ?? UUID(), name: categoryName.trimmingCharacters(in: .whitespacesAndNewlines), color: categoryColor, isPinboard: categoryPinboard)
                        Task {
                            do { try await model.store.saveCategory(category); await model.refresh(); categoryID = nil; categoryName = ""; categoryPinboard = false }
                            catch { feedback = error.localizedDescription }
                        }
                    }.disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(L("删除分类后记录移入未分类，并恢复全局保留规则。固定分类由你手动整理，AI 不会自动放入。")).font(.caption).foregroundStyle(.secondary)
                }
                if !feedback.isEmpty { Section { Text(feedback).font(.subheadline) } }
            }.id(model.preferences.language).navigationTitle(L("设置")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("关闭")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(saving ? L("保存中…") : L("保存")) { save() }.disabled(saving) }
                }
        }.tint(.clipori)
            .onAppear {
                draft = model.preferences
                retention = draft.retentionDays
                do { secret = try Keychain.read(service: "app.clipori") } catch { feedback = error.localizedDescription }
            }
            .confirmationDialog(L("启用自动清理？超期记录将被删除。"), isPresented: $confirmingRetention, titleVisibility: .visible) { Button(L("保存并清理"), role: .destructive) { persist() } }
    }
    private func save() {
        draft.retentionDays = retention
        if draft.retentionDays > 0 && (model.preferences.retentionDays == 0 || draft.retentionDays < model.preferences.retentionDays) { confirmingRetention = true }
        else { persist() }
    }
    private func persist() {
        saving = true
        Task {
            do { try await model.updatePreferences(draft, secret: secret); feedback = L("设置已保存") }
            catch { feedback = error.localizedDescription }
            saving = false
        }
    }
}

private struct MobileCloudSettings: View {
    @ObservedObject var sync: CloudSyncController
    @Binding var enabled: Bool
    var body: some View {
        Toggle(L("同步备忘与分类"), isOn: $enabled).disabled(!sync.available)
        Text(sync.available ? L("同一 Apple 账号即可互通。设备设置和 API Key 不参与同步。") : L("此开发构建尚未配置 Apple 签名和 CloudKit 容器。可正常本地使用。"))
            .font(.caption).foregroundStyle(.secondary)
        if sync.available {
            Text(sync.status).font(.caption)
            Button(L("立即同步")) { Task { await sync.syncNow() } }.disabled(sync.isSyncing || !enabled)
        }
    }
}
