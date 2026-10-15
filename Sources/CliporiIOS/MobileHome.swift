import SwiftUI
import CliporiCore

struct MobileHome: View {
    @StateObject var model: MobileModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var editing: MemoryEditor?
    @State private var settings = false
    @State private var deleting: Memory?
    @State private var copied = false

    private var motion: Animation? { reducedMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("关键词，或问问以前的自己…"), text: $model.query).submitLabel(.search).onSubmit { model.aiSearch() }.accessibilityIdentifier("memory-search")
                        if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
                        Button { model.aiSearch() } label: {
                            if model.searchingAI { ProgressView().controlSize(.small) }
                            else { Image(systemName: "sparkles").foregroundStyle(Color.clipori) }
                        }.accessibilityLabel(L("AI 搜索")).disabled(model.searchingAI)
                    }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 17))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryButton(L("全部记忆"), id: nil, color: "lavender")
                            ForEach(model.categories) { category in categoryButton(category.displayName, id: category.id, color: category.color) }
                        }
                    }
                    if !model.aiAnswer.isEmpty {
                        Label(model.aiAnswer, systemImage: "sparkles").font(.subheadline).lineSpacing(5).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading).background(Color.clipori.opacity(0.09), in: RoundedRectangle(cornerRadius: 18)).textSelection(.enabled)
                    }
                    if model.loading { ProgressView().frame(maxWidth: .infinity).padding(60) }
                    else if model.records.isEmpty {
                        VStack(spacing: 16) {
                            MascotView(size: 76)
                            Text(model.query.isEmpty ? L("把灵感，留在手边。") : L("这里还没有找到这段记忆")).font(.headline)
                            Text(model.query.isEmpty ? L("粘贴一段内容，或写下新的备忘。\n想起时，再来找我。") : L("换个关键词，或点星星用 AI 找找看。"))
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(model.records) { record in
                                MemoryTile(record: record, category: model.categories.first { $0.id == record.categoryID }) { edit(record) }
                                    .contextMenu {
                                        Button(L("复制"), systemImage: "doc.on.doc") { UIPasteboard.general.string = record.body; copied = true }
                                        Button(L("编辑"), systemImage: "square.and.pencil") { edit(record) }
                                        Button(L("删除"), systemImage: "trash", role: .destructive) { deleting = record }
                                    }
                                    .onAppear { if record.id == model.records.last?.id { Task { await model.loadMore() } } }
                                    .transition(.opacity.combined(with: .offset(y: 8)))
                            }
                        }.animation(motion, value: model.records.map(\.id))
                    }
                }.padding(.horizontal, 20).padding(.bottom, 100).id(model.preferences.language)
            }.background(Color.clipori.opacity(0.045))
                .scrollDismissesKeyboard(.interactively)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        PasteButton(payloadType: String.self) { strings in Task { for string in strings { await model.capture(string) } } }
                            .tint(.clipori).labelStyle(.titleAndIcon)
                        Spacer()
                        Button { edit(nil) } label: { Label(L("新的备忘"), systemImage: "plus").fontWeight(.semibold).padding(.vertical, 4) }
                            .buttonStyle(.borderedProminent).tint(.clipori)
                    }.padding(.horizontal, 24).padding(.vertical, 12).background(.ultraThinMaterial)
                }
        }.tint(.clipori).environment(\.locale, L10n.locale)
            .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
            .task { await model.start() }
            .onChange(of: phase) { _, value in if value == .active { Task { await model.refresh(); await model.cloud.syncNow() } } }
            .sheet(isPresented: $settings) { MobileSettings(model: model) }
            .sheet(item: $editing) { editor in MobileEditor(editor: editor, categories: model.categories) }
            .alert(L("小提示"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L("好")) { model.error = nil } } message: { Text(model.error ?? "") }
            .overlay(alignment: .top) {
                if copied { Label(L("已复制"), systemImage: "checkmark").font(.subheadline.weight(.medium)).padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 12).transition(.opacity) }
            }
            .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { copied = false } } }
            .confirmationDialog(L("删除这条备忘？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(L("删除"), role: .destructive) { if let record = deleting { Task { await model.delete(record) } }; deleting = nil }
            }
    }
    private var header: some View {
        HStack(spacing: 12) {
            MascotView(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clipori").font(.system(size: 27, weight: .bold, design: .rounded))
                Text(L("日常里的小小记忆")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { settings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3).padding(12).background(.background, in: Circle()) }.accessibilityLabel(L("设置"))
        }.padding(.top, 18).padding(.bottom, 4)
    }
    private func categoryButton(_ name: String, id: UUID?, color: String) -> some View {
        Button { model.categoryID = id } label: {
            HStack(spacing: 6) {
                if id != nil { Circle().fill(Color.category(color)).frame(width: 6, height: 6) }
                Text(name).font(.subheadline.weight(.medium))
            }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(model.categoryID == id ? Color.clipori.opacity(0.18) : Color.primary.opacity(0.035), in: Capsule())
        }.foregroundStyle(model.categoryID == id ? Color.clipori : .secondary)
    }
    private func edit(_ record: Memory?) {
        editing = MemoryEditor(record: record, store: model.store) { [weak model] in await model?.refresh() }
    }
}

private struct MemoryTile: View {
    let record: Memory
    let category: MemoryCategory?
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(category?.displayName ?? L("未分类"), systemImage: record.kind == .image ? "photo" : record.kind == .link ? "link" : "text.alignleft")
                        .font(.caption.weight(.medium)).foregroundStyle(Color.category(category?.color ?? "lavender"))
                    Spacer()
                    if record.keepForever { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text(record.displayTitle).font(.system(.headline, design: .rounded)).lineLimit(2)
                Text(String(record.body.prefix(600))).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5).lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
                HStack { Text(record.displaySource); Spacer(); Text(record.createdAt, format: .dateTime.month().day()) }.font(.caption2).foregroundStyle(.tertiary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 23))
                .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.category(category?.color ?? "lavender").opacity(0.16), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(record.displayTitle)
    }
}
