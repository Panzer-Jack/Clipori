import SwiftUI
import CliporiCore
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var app: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
    @State private var addingCategory = false
    @State private var launchAtLogin = false
    @State private var showRetentionConfirmation = false
    @State private var pendingPreferences: Preferences?
    @State private var showClearHistoryConfirmation = false
    @State private var preparingHistoryClear = false

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
            if selectedTab == 2 {
                categorySettings.padding(.horizontal, 26).padding(.top, 4).padding(.bottom, 18)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch selectedTab {
                        case 1: aiSettings
                        case 3: dataSettings
                        case 4: ShortcutSettingsView(shortcuts: $draft.shortcuts, recording: { app.onShortcutRecording?($0) })
                        default: generalSettings
                        }
                    }.padding(.horizontal, 26).padding(.vertical, 4)
                }
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
            .task(id: selectedTab) { if selectedTab == 1 { await app.refreshUnclassifiedCount() } }
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("背景不透明度"))
                    Spacer()
                    Text(draft.shelfBackgroundOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $draft.shelfBackgroundOpacity, in: 0...1, step: 0.05) {
                    Text(L("背景不透明度"))
                }.labelsHidden().disabled(reduceTransparency)
                Text(L(reduceTransparency
                    ? "系统已开启“降低透明度”，卡片栏使用不透明背景。"
                    : "数值越高，底下窗口的干扰越少；100% 完全不透明。保存设置后生效。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Picker(L("语言"), selection: $draft.language) { ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) } }
            Toggle(L("暂停自动记录"), isOn: $draft.capturePaused)
            Toggle(L("登录时启动"), isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { feedback = L("登录启动设置失败：") + error.localizedDescription }
            }
            Divider()
            retentionSettings
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L("历史排序"), icon: "arrow.up.arrow.down")
                Toggle(L("使用后移到最前"), isOn: $draft.moveToFrontAfterUse)
                Text(L("复制或粘贴卡片后，下次打开时排到最前，当前卡片位置不变。外部重复复制或剪切也会前移。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L("快捷粘贴"), icon: "arrow.up.doc")
                Text(L("双击卡片或按回车，将内容直接粘贴到之前的应用。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Label(L(app.hasAccessibilityPermission ? "已授权" : "需要辅助功能权限"),
                          systemImage: app.hasAccessibilityPermission ? "checkmark.circle.fill" : "lock.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if !app.hasAccessibilityPermission {
                        Button(L("申请辅助功能权限")) { app.onRequestAccessibility?() }
                    }
                }
                if !app.hasAccessibilityPermission {
                    Text(L("未授权也可单击复制，再到目标应用按 ⌘V。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
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
            Text(L("仅自动分类开启后新收录的记录，不处理历史记录，也不覆盖手动分类。"))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(L("分类未分类记录")) { Task { await app.classifyUnclassifiedRecords() } }
                        .disabled(app.isClassifyingHistory || app.unclassifiedCount == 0 || !app.preferences.ai.isConfigured)
                    if app.isClassifyingHistory {
                        ProgressView().controlSize(.small)
                        Text(LF("已处理 %d / %d 条", app.classificationCompleted, app.classificationTotal))
                        Button(L("停止")) { app.stopClassification() }
                    } else {
                        Text(LF("%d 条待分类", app.unclassifiedCount))
                    }
                }.font(.system(size: 12))
                Text(L("手动处理当前未分类记录，使用已保存的 AI 配置；无需开启自动分类。没有合适分类的记录会保留在未分类。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if !app.classificationStatus.isEmpty {
                    Text(app.classificationStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Text(L("分类会向你配置的 AI 服务发送记录标题和文字内容；图片不会发送。AI 搜索只发送问题和候选片段，API Key 不随记录同步。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            Text(L("每日备忘录可通过 AI 整理当天剪贴板，生成可编辑的事项建议，选择后加入。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L("文字片段与已有事项会发送至你在设置中配置的 AI 服务，图片不会发送。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private var categorySettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(L("为记忆找到位置"), icon: "tag")
                Spacer()
                Text(L("拖动调整顺序")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            List {
                ForEach(app.categories) { category in
                    CategorySettingsRow(category: category, save: { value in
                        try await app.store.saveCategory(value)
                        await app.refreshCategories(); feedback = L("分类已保存。")
                    }, delete: {
                        try await app.store.deleteCategory(id: category.id)
                        await app.refreshCategories()
                    }, reportError: { feedback = L("保存失败：") + $0.localizedDescription })
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .moveDisabled(app.reorderingCategories)
                }
                .onMove(perform: moveCategories)
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 38)
                .frame(minHeight: 212)
                .accessibilityIdentifier("category-order-list")
            Divider()
            Text(L("添加分类")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                TextField(L("分类名称"), text: $categoryName).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("new-category-name")
                Button(L("添加分类")) {
                    let category = MemoryCategory(name: categoryName.trimmingCharacters(in: .whitespacesAndNewlines), color: categoryColor, isPinboard: categoryPinboard)
                    addingCategory = true
                    Task {
                        defer { addingCategory = false }
                        do { try await app.store.saveCategory(category); await app.refreshCategories(); categoryName = ""; categoryPinboard = false; feedback = L("分类已保存。") }
                        catch { feedback = error.localizedDescription }
                    }
                }.disabled(addingCategory || categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                CategoryColorPicker(selection: $categoryColor)
                Spacer()
                Toggle(L("固定分类"), isOn: $categoryPinboard)
                    .help(L("固定分类（Pinboard）· 其中记录不自动清理"))
            }
            Text(L("删除分类后记录移入未分类，并恢复全局保留规则。固定分类由你手动整理，AI 不会自动放入。")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func moveCategories(from offsets: IndexSet, to destination: Int) {
        var ordered = app.categories
        ordered.move(fromOffsets: offsets, toOffset: destination)
        guard ordered != app.categories else { return }
        Task {
            do { try await app.reorderCategories(ordered); feedback = L("分类顺序已保存。") }
            catch { feedback = L("保存失败：") + error.localizedDescription }
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
            Text(L("每日备忘录仅保存在本机，长期保留，不参与 iCloud 同步、过期清理或下方的清空操作。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button(app.isClearingHistory ? L("正在清空…") : L("清空所有记录…"), role: .destructive) {
                    preparingHistoryClear = true
                    Task {
                        defer { preparingHistoryClear = false }
                        do {
                            app.totalCount = try await app.store.count()
                            if app.totalCount > 0 { showClearHistoryConfirmation = true }
                        } catch { feedback = L("清空失败：") + error.localizedDescription }
                    }
                }.foregroundStyle(.red)
                    .disabled(app.totalCount == 0 || app.isClearingHistory || preparingHistoryClear)
                    .accessibilityIdentifier("clear-history")
                Text(L("删除全部文字、图片和备忘，包括固定记录；保留分类及设置。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .alert(LF("清空全部 %d 条记录？", app.totalCount), isPresented: $showClearHistoryConfirmation) {
                Button(L("取消"), role: .cancel) {}.keyboardShortcut(.defaultAction)
                Button(L("清空所有记录"), role: .destructive) {
                    Task {
                        do {
                            let count = try await app.clearHistory()
                            feedback = LF("已清空 %d 条记录。", count)
                        } catch { feedback = L("清空失败：") + error.localizedDescription }
                    }
                }.accessibilityIdentifier("confirm-clear-history")
            } message: {
                Text(L("所有文字、图片、手动备忘、固定记录及固定分类中的记录都会删除，已打开的备忘窗口会关闭。分类、快捷键和 AI 配置保留。此操作无法撤销。")
                     + "\n\n" + L("使用 iCloud 同步时，其他设备上的对应记录也会删除。")
                     + "\n\n" + L("每日备忘录会保留。"))
            }
        }
        .task {
            do { app.totalCount = try await app.store.count() }
            catch { feedback = error.localizedDescription }
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
