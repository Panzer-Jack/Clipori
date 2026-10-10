import SwiftUI
import CliporiCore
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var app: AppModel
    @State private var draft = Preferences()
    @State private var apiKey = ""
    @State private var selectedTab = 0
    @State private var feedback = ""
    @State private var testing = false
    @State private var saving = false
    @State private var retentionChoice = 0
    @State private var ignoredApps = ""
    @State private var categoryName = ""
    @State private var categoryColor = "lavender"
    @State private var categoryPinboard = false
    @State private var editingCategory: UUID?
    @State private var launchAtLogin = false
    @State private var showRetentionConfirmation = false
    @State private var pendingPreferences: Preferences?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MascotView(size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("让 Clipori 更懂你")).font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(L("一点小设置，刚刚好的记忆空间。")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Picker(L("设置"), selection: $selectedTab) {
                Text(L("通用")).tag(0); Text("AI").tag(1); Text(L("分类")).tag(2); Text(L("数据")).tag(3); Text(L("快捷键")).tag(4)
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case 1: aiSettings
                    case 2: categorySettings
                    case 3: dataSettings
                    case 4: ShortcutSettingsView(shortcuts: $draft.shortcuts, recording: { app.onShortcutRecording?($0) })
                    default: generalSettings
                    }
                }.padding(.horizontal, 26).padding(.vertical, 4)
            }
            Divider()
            HStack {
                Text(feedback).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if selectedTab != 2 {
                    Button(saving ? L("保存中…") : L("保存设置")) { save() }.buttonStyle(.borderedProminent).tint(.clipori).disabled(saving)
                }
            }.padding(20)
        }.frame(width: 560, height: 590)
            .id(app.preferences.language)
            .onAppear {
                draft = app.preferences; ignoredApps = draft.ignoredApps.joined(separator: "\n")
                retentionChoice = draft.retentionDays
                selectedTab = app.requestedSettingsTab; app.requestedSettingsTab = 0
                categoryPinboard = app.requestNewPinboard; app.requestNewPinboard = false
                do { apiKey = try Keychain.read(service: app.keychainService) } catch { feedback = error.localizedDescription }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            .alert(L("启用自动清理？"), isPresented: $showRetentionConfirmation) {
                Button(L("取消"), role: .cancel) { pendingPreferences = nil }
                Button(L("保存并清理"), role: .destructive) { if let value = pendingPreferences { persist(value) } }
            } message: { Text(L("过期记录将被删除，包括手动新建和编辑过的记录。固定记录和固定分类中的内容会保留。")) }
            .environment(\.locale, L10n.locale)
    }
    private var generalSettings: some View {
        Group {
            sectionTitle(L("随时唤出"), icon: "keyboard")
            HStack { Text(L("显示 / 收起卡片栏")); Spacer(); KeyHint(key: draft.shortcuts[.activate].display) }.font(.system(size: 13))
            Button(L("自定义各个快捷键")) { selectedTab = 4 }
            Divider()
            Picker(L("外观"), selection: $draft.appearance) { Text(L("跟随系统")).tag("system"); Text(L("浅色")).tag("light"); Text(L("深色")).tag("dark") }
            Picker(L("语言"), selection: $draft.language) { ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) } }
            Toggle(L("减少动效"), isOn: $draft.reduceMotion)
            Toggle(L("暂停自动记录"), isOn: $draft.capturePaused)
            Toggle(L("登录时启动"), isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { feedback = L("登录启动设置失败：") + error.localizedDescription }
            }
            Divider()
            retentionSettings
            Divider()
            sectionTitle(L("粘贴到原应用"), icon: "arrow.up.doc")
            Text(L("直接粘贴需要辅助功能权限；未授权时，选中的内容会先复制到剪贴板，可手动按 ⌘V 粘贴。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button(L("打开辅助功能设置")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }
        }
    }
    private var aiSettings: some View {
        Group {
            sectionTitle(L("你的 AI，你来选择"), icon: "sparkles")
            Picker(L("接口格式"), selection: $draft.ai.format) {
                ForEach(AIFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.onChange(of: draft.ai.format) { old, new in if draft.ai.baseURL == old.defaultBaseURL { draft.ai.baseURL = new.defaultBaseURL } }
            LabeledContent(L("接口地址")) { TextField("https://…/v1", text: $draft.ai.baseURL).textFieldStyle(.roundedBorder) }
            LabeledContent(L("模型名称")) { TextField(L("服务商提供的模型 ID"), text: $draft.ai.model).textFieldStyle(.roundedBorder) }
            LabeledContent("API Key") { SecureField(L("仅保存在本机钥匙串"), text: $apiKey).textFieldStyle(.roundedBorder) }
            HStack {
                Button(testing ? L("正在连接…") : L("测试连接")) {
                    testing = true; feedback = ""
                    let config = draft.ai; let secret = apiKey
                    Task {
                        do { try await AIClient(configuration: config, apiKey: secret).testConnection(); feedback = L("连接成功，可以开始找回记忆了。") }
                        catch { feedback = error.localizedDescription }
                        testing = false
                    }
                }.disabled(testing)
                if testing { ProgressView().controlSize(.small) }
                Spacer()
            }
            Divider()
            Toggle(L("AI 自动分类"), isOn: $draft.ai.autoClassify)
            Text(L("开启后，会向你配置的服务发送待分类的记录内容。AI 搜索只发送问题和候选片段；API Key 不随记录同步。"))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button(L("重试待分类记录")) { app.startClassification(); feedback = L("已安排后台分类。") }.disabled(!app.preferences.ai.autoClassify)
        }
    }
    private var categorySettings: some View {
        Group {
            sectionTitle(L("为记忆找到位置"), icon: "tag")
            ForEach(app.categories) { category in
                HStack(spacing: 10) {
                    Image(systemName: category.isPinboard ? "pin.fill" : "tag").font(.system(size: 16))
                        .foregroundStyle(Color.category(category.color))
                    Text(category.displayName)
                    if category.isPinboard { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                    Spacer()
                    Button(L("编辑")) { categoryName = category.name; categoryColor = category.color; categoryPinboard = category.isPinboard; editingCategory = category.id }.buttonStyle(.borderless)
                    Button { Task { do { try await app.store.deleteCategory(id: category.id); await app.refreshCategories() } catch { feedback = error.localizedDescription } } } label: { Image(systemName: "trash").foregroundStyle(.secondary) }.buttonStyle(.borderless).help(L("删除分类，记录会移入未分类"))
                }.padding(.vertical, 4)
            }
            Divider()
            TextField(L("分类名称"), text: $categoryName).textFieldStyle(.roundedBorder)
            Toggle(L("固定分类（Pinboard）· 其中记录不自动清理"), isOn: $categoryPinboard)
            HStack {
                ForEach(["lavender", "blue", "mint", "peach", "pink"], id: \.self) { color in
                    Button { categoryColor = color } label: {
                        Circle().fill(Color.category(color)).frame(width: 22, height: 22).overlay(Circle().strokeBorder(.white, lineWidth: categoryColor == color ? 3 : 0)).padding(2)
                    }.buttonStyle(.plain).accessibilityLabel(color)
                }
                Spacer()
                Button(editingCategory == nil ? L("添加分类") : L("保存分类")) {
                    let category = MemoryCategory(id: editingCategory ?? UUID(), name: categoryName.trimmingCharacters(in: .whitespacesAndNewlines), color: categoryColor, isPinboard: categoryPinboard)
                    Task {
                        do { try await app.store.saveCategory(category); await app.refreshCategories(); categoryName = ""; editingCategory = nil; categoryPinboard = false; feedback = L("分类已保存。") }
                        catch { feedback = error.localizedDescription }
                    }
                }.disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(L("删除分类后记录移入未分类，并恢复全局保留规则。固定分类由你手动整理，AI 不会自动放入。")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private var dataSettings: some View {
        Group {
            CloudSettingsSection(sync: app.cloudSync, enabled: $draft.iCloudEnabled)
            Text(L("图片当前仅保存在这台 Mac；图片跨设备同步与文字识别将在后续版本支持。")).font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            sectionTitle(L("忽略这些应用"), icon: "eye.slash")
            Text(L("每行一个应用 Bundle ID，例如 com.apple.keychainaccess。")).font(.system(size: 11)).foregroundStyle(.secondary)
            TextEditor(text: $ignoredApps).font(.system(size: 12, design: .monospaced)).frame(height: 65).border(Color.secondary.opacity(0.2))
            Divider()
            HStack { Text(L("本地记录")); Spacer(); Text(LF("%d 条", app.totalCount)).foregroundStyle(.secondary) }
            Button(L("在 Finder 中查看数据文件")) { NSWorkspace.shared.open(app.dataDirectory) }
        }
    }
    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.clipori)
    }
    private var retentionSettings: some View {
        Group {
            sectionTitle(L("记多久，由你决定"), icon: "clock.arrow.circlepath")
            Picker(L("历史保留"), selection: $retentionChoice) {
                ForEach(HistoryRetention.presets) { Text($0.title).tag($0.days) }
                if !HistoryRetention.presets.contains(where: { $0.days == retentionChoice }) { Text(LF("%d 天（旧设置）", retentionChoice)).tag(retentionChoice) }
            }
            Text(L("默认保留 1 个月，按时间清理。固定记录和固定分类不受期限影响，编辑不会延长保留时间。")).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
    private func save() {
        var value = draft
        value.retentionDays = retentionChoice
        value.ignoredApps = ignoredApps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if value.retentionDays > 0 && (app.preferences.retentionDays == 0 || value.retentionDays < app.preferences.retentionDays) {
            pendingPreferences = value; showRetentionConfirmation = true
        } else { persist(value) }
    }
    private func persist(_ value: Preferences) {
        saving = true
        Task {
            do {
                try Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), service: app.keychainService)
                try await app.updatePreferences(value); draft = value; feedback = L("设置已保存。")
            } catch { feedback = error.localizedDescription }
            saving = false
        }
    }
}

private struct CloudSettingsSection: View {
    @ObservedObject var sync: CloudSyncController
    @Binding var enabled: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("iCloud 同步"), isOn: $enabled).disabled(!sync.available)
            Text(L("使用同一 Apple 账号同步备忘与分类。API Key 和设备设置留在本机。")).font(.system(size: 12)).foregroundStyle(.secondary)
            if sync.available {
                HStack { Text(sync.status).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L("立即同步")) { Task { await sync.syncNow() } }.disabled(sync.isSyncing || !enabled) }
            } else { Text(L("开发构建需先配置 Apple 签名和 CloudKit 容器。当前可正常本地使用。")).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
