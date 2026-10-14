import SwiftUI
import CliporiCore

enum DailyNoteField: Hashable { case item(UUID), task(UUID) }

struct DailyNotesView: View {
    @ObservedObject var model: DailyNotesModel
    @ObservedObject var app: AppModel
    @ObservedObject var assistant: DailyNoteAssistant
    @FocusState private var focus: DailyNoteField?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 208)
            Divider()
            VStack(spacing: 0) {
                if let note = model.note {
                    header(note)
                    Divider()
                    if note.items.isEmpty { emptyPage }
                    else { table(note) }
                } else {
                    Spacer()
                    if model.isLoading { ProgressView() }
                    else { Text(L("打开每日备忘录，开始记录今天。")).foregroundStyle(.secondary) }
                    Spacer()
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .id(app.preferences.language)
        .environment(\.locale, L10n.locale)
        .onChange(of: model.note?.day) { _, _ in focus = nil; assistant.dismiss() }
        .sheet(isPresented: $assistant.isPresented, onDismiss: { assistant.cancel() }) {
            DailyNoteAISheet(assistant: assistant, model: model) {
                assistant.dismiss(); app.requestedSettingsTab = 1; app.onSettings?()
            }.environment(\.locale, L10n.locale)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(L("每日备忘录"), systemImage: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold)).padding(20)
            Button {
                Task { await model.refreshToday(); await model.selectDay(model.today) }
            } label: {
                Label(L("回到今天"), systemImage: "sun.max").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(QuietButton(selected: true)).foregroundStyle(Color.clipori).padding(.horizontal, 14)
                .disabled(model.isLoading).accessibilityIdentifier("daily-today")
            Text(L("往期备忘录")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 10)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.days, id: \.self) { day in
                        Button { Task { await model.selectDay(day) } } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "doc.text").foregroundStyle(day == model.note?.day ? Color.clipori : Color.secondary)
                                Text(day).font(.system(size: 12, weight: day == model.note?.day ? .semibold : .regular)).monospacedDigit()
                                Spacer(minLength: 0)
                                if day == model.today { Text(L("今天")).font(.system(size: 10)).foregroundStyle(.secondary) }
                            }.padding(.horizontal, 12).padding(.vertical, 10)
                                .background(day == model.note?.day ? Color.clipori.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.isLoading)
                            .accessibilityIdentifier("daily-day-\(day)")
                            .accessibilityAddTraits(day == model.note?.day ? .isSelected : [])
                    }
                }.padding(.horizontal, 10)
            }
            Label(L("每日一页，接着推进。"), systemImage: "leaf")
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(20)
        }.frame(maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor))
    }

    private func header(_ note: DailyNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(LF("%@ 备忘录", String(note.day.suffix(5)).replacingOccurrences(of: "-", with: ".")))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(model.isHistorical ? L("往期备忘录 · 修改仅影响本页") : L("记录今天要推进的事情"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { assistant.start(for: note) } label: { Label(L("AI 整理"), systemImage: "sparkles") }
                    .buttonStyle(QuietButton(selected: true)).foregroundStyle(Color.clipori)
                    .disabled(model.isLoading).accessibilityIdentifier("daily-ai-generate")
                    .help(L("文字片段与已有事项会发送至你在设置中配置的 AI 服务，图片不会发送。"))
                Button(action: addItem) { Label(L("添加事项"), systemImage: "plus") }
                    .buttonStyle(QuietButton()).foregroundStyle(.secondary)
                    .disabled(model.isLoading).accessibilityIdentifier("daily-add-item")
            }
            HStack(spacing: 6) {
                Image(systemName: "pin.fill").foregroundStyle(Color.clipori)
                Text(L("每天保留，全部完成后停止延续"))
                Spacer()
                Text(LF("%d 项事项 · %d 项子任务", note.items.count, note.items.reduce(0) { $0 + $1.tasks.count }))
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 28).padding(.vertical, 24)
    }

    private func table(_ note: DailyNote) -> some View {
        GeometryReader { geometry in
            let itemWidth = max(205, (geometry.size.width - 56) * 0.34)
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(L("事项")).frame(width: itemWidth - 32, alignment: .leading).padding(16)
                        Divider()
                        Text(L("子任务")).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }.font(.system(size: 13, weight: .semibold)).frame(height: 46)
                        .background(Color.primary.opacity(0.025))
                    ForEach(note.items) { item in
                        Divider()
                        DailyItemRow(model: model, item: item, itemWidth: itemWidth, focus: $focus)
                    }
                }
                .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                .padding(.horizontal, 28).padding(.top, 20)
                Button(action: addItem) { Label(L("添加事项"), systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 44).padding(.vertical, 18)
            }.disabled(model.isLoading)
        }
    }

    private var emptyPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist").font(.system(size: 40, weight: .light)).foregroundStyle(Color.clipori)
            Text(L(model.isHistorical ? "这一天还没有事项" : "给今天留一份清单")).font(.system(size: 19, weight: .medium))
            Text(L(model.isHistorical ? "可以补充当天的记录，其他日期的内容会保留原样。" : "添加事项和子任务；点亮 pin，让未完成的事情延续到下一天。"))
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: addItem) { Label(L("添加第一件事"), systemImage: "plus") }
                .buttonStyle(QuietButton(selected: true)).disabled(model.isLoading)
            Button {
                if let note = model.note { assistant.start(for: note) }
            } label: { Label(L("从当天剪贴板生成"), systemImage: "sparkles") }
                .buttonStyle(QuietButton(selected: true)).foregroundStyle(Color.clipori).disabled(model.isLoading)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).lineLimit(2)
                    Button(L("重试")) { Task { await model.refreshToday() } }
                } else {
                    Label(L(model.isDirty ? "正在保存…" : "已保存到本机"), systemImage: model.isDirty ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.deletedSnapshot != nil { Button(L("撤销删除")) { model.undoDeletion() }.buttonStyle(.plain).foregroundStyle(Color.clipori) }
            }.font(.system(size: 11)).padding(.horizontal, 22).padding(.vertical, 12)
        }
    }

    private func addItem() {
        if let id = model.addItem() { focus = .item(id) }
    }
}

private struct DailyItemRow: View {
    @ObservedObject var model: DailyNotesModel
    let item: DailyItem
    let itemWidth: CGFloat
    let focus: FocusState<DailyNoteField?>.Binding
    @State private var hideCompleted = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if item.tasks.isEmpty {
                        completionButton(item.completed) { model.updateItem(item.id) { $0.isCompleted.toggle() } }
                    }
                    TextField(L("事项名称"), text: itemBinding(\.title), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 14, weight: .medium)).lineLimit(1...12)
                        .strikethrough(item.completed).foregroundStyle(item.completed ? .secondary : .primary)
                        .focused(focus, equals: .item(item.id)).accessibilityIdentifier("daily-item-title-\(item.id)")
                    Button { model.updateItem(item.id) { $0.isPinned.toggle() } } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(item.isPinned ? Color.clipori : Color.secondary)
                    }.buttonStyle(.plain).padding(.top, 2)
                        .help(L(item.isPinned ? "取消跨天保留" : "每天保留，全部完成后停止延续"))
                        .accessibilityLabel(L(item.isPinned ? "取消跨天保留" : "跨天保留"))
                        .accessibilityIdentifier("daily-pin-\(item.id)")
                }
                TextField(L("备注或链接（可选）"), text: itemBinding(\.note), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1...15)
                DailyNoteLinks(text: item.title + " " + item.note)
                DailyNoteEvidenceView(evidence: (item.evidence ?? []) + item.tasks.flatMap { $0.evidence ?? [] })
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        .draggable("daily-item:\(item.id)").help(L("拖动调整顺序"))
                    if item.isPinned {
                        Text(L(item.completed ? "已完成 · 明日不再延续" : "每天保留"))
                            .foregroundStyle(item.completed ? Color.secondary : Color.clipori)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button(L("上移")) { moveUp() }
                        Button(L("下移")) { moveDown() }
                        Divider()
                        Button(L("删除事项"), role: .destructive) { model.deleteItem(item.id) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().help(L("事项操作"))
                }.font(.system(size: 10))
            }.padding(16).frame(width: itemWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(item.tasks.filter { !hideCompleted || !$0.isCompleted }) { task in
                    taskRow(task)
                }
                HStack(spacing: 14) {
                    Button { addTask() } label: { Label(L("添加子任务"), systemImage: "plus") }
                        .buttonStyle(.plain).accessibilityIdentifier("daily-add-task-\(item.id)")
                    if item.tasks.contains(where: \.isCompleted) {
                        Button { hideCompleted.toggle() } label: {
                            Text(hideCompleted ? LF("展开已完成（%d）", item.tasks.filter(\.isCompleted).count) : L("折叠已完成"))
                        }.buttonStyle(.plain)
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1).offset(x: itemWidth) }
        .background(dropTargeted ? Color.clipori.opacity(0.08) : .clear)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, value.hasPrefix("daily-item:"), let id = UUID(uuidString: String(value.dropFirst("daily-item:".count))) else { return false }
            model.moveItem(id, before: item.id); return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func taskRow(_ task: DailyTask) -> some View {
        HStack(alignment: .top, spacing: 8) {
            completionButton(task.isCompleted) { model.updateTask(task.id, in: item.id) { $0.isCompleted.toggle() } }
                .accessibilityIdentifier("daily-check-\(task.id)")
            VStack(alignment: .leading, spacing: 4) {
                TextField(L("写下一个子任务"), text: Binding(get: { task.title }, set: { value in
                    model.updateTask(task.id, in: item.id) { $0.title = value }
                }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...12)
                    .strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .focused(focus, equals: .task(task.id)).onSubmit { addTask(after: task.id) }
                    .accessibilityIdentifier("daily-task-title-\(task.id)")
                DailyNoteLinks(text: task.title)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(L("上移")) {
                    if let index = item.tasks.firstIndex(where: { $0.id == task.id }), index > 0 {
                        model.moveTask(task.id, before: item.tasks[index - 1].id, in: item.id)
                    }
                }
                Button(L("下移")) {
                    if let index = item.tasks.firstIndex(where: { $0.id == task.id }), index + 1 < item.tasks.count {
                        model.moveTask(item.tasks[index + 1].id, before: task.id, in: item.id)
                    }
                }
                Button(L("删除子任务"), role: .destructive) { model.deleteTask(task.id, in: item.id) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(.tertiary) }
                .menuStyle(.borderlessButton).fixedSize().help(L("子任务操作"))
                .draggable("daily-task:\(item.id):\(task.id)")
        }.dropDestination(for: String.self) { values, _ in
            let prefix = "daily-task:\(item.id):"
            guard let value = values.first, value.hasPrefix(prefix), let id = UUID(uuidString: String(value.dropFirst(prefix.count))) else { return false }
            model.moveTask(id, before: task.id, in: item.id); return true
        }
    }

    private func completionButton(_ completed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: completed ? "checkmark.square.fill" : "square")
                .font(.system(size: 18, weight: .light)).foregroundStyle(completed ? Color.clipori.opacity(0.65) : Color.secondary)
        }.buttonStyle(.plain).accessibilityLabel(L(completed ? "标记为未完成" : "标记为完成"))
    }

    private func itemBinding(_ keyPath: WritableKeyPath<DailyItem, String>) -> Binding<String> {
        Binding(get: { item[keyPath: keyPath] }, set: { value in model.updateItem(item.id) { $0[keyPath: keyPath] = value } })
    }

    private func addTask(after id: UUID? = nil) {
        if let taskID = model.addTask(to: item.id, after: id) { focus.wrappedValue = .task(taskID) }
    }

    private func moveUp() {
        guard let items = model.note?.items, let index = items.firstIndex(where: { $0.id == item.id }), index > 0 else { return }
        model.moveItem(item.id, before: items[index - 1].id)
    }

    private func moveDown() {
        guard let items = model.note?.items, let index = items.firstIndex(where: { $0.id == item.id }), index + 1 < items.count else { return }
        model.moveItem(items[index + 1].id, before: item.id)
    }
}

private struct DailyNoteLinks: View {
    let text: String
    private var urls: [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen: Set<URL> = []
        return Array(detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && seen.insert($0).inserted }.prefix(3))
    }
    var body: some View {
        ForEach(urls, id: \.self) { url in
            Link(destination: url) { Label(url.host ?? L("打开链接"), systemImage: "arrow.up.right.square").lineLimit(1) }
                .font(.system(size: 11)).help(url.absoluteString)
        }
    }
}
