import SwiftUI
import CliporiCore

struct ShelfView: View {
    static let windowPadding: CGFloat = 10
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @FocusState private var cardsFocused: Bool
    @State private var hoveredCardID: UUID?
    @State private var dropCategoryID: UUID?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var categoryAnimation

    private var animation: Animation? { model.motion ? .spring(response: 0.34, dampingFraction: 0.86) : nil }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 12)
            categoryBar.padding(.horizontal, 22).padding(.bottom, 12)
            if !model.aiAnswer.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.clipori)
                    Text(model.aiAnswer).font(.system(size: 12)).lineLimit(3).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button { model.cancelAI() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L("退出 AI 结果"))
                }.padding(12).background(Color.clipori.opacity(0.09), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 22).padding(.bottom, 10)
            }
            cards
            footer.padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                ShelfGlass(reduceTransparency: reduceTransparency)
                if reduceTransparency {
                    Rectangle().fill(scheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
                } else {
                    Rectangle().fill(scheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.09 : 0.24), .clear, Color.clipori.opacity(0.018)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.38 : 0.85), .white.opacity(0.08), .white.opacity(scheme == .dark ? 0.18 : 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
        .padding(Self.windowPadding)
        .id(model.preferences.language)
        .environment(\.locale, L10n.locale)
        .focusable()
        .focusEffectDisabled()
        .focused($cardsFocused)
        .onChange(of: model.presentation) { _, _ in searchFocused = true }
        .onChange(of: model.memoryDrag?.token) { _, token in
            hoveredCardID = nil
            if token == nil { dropCategoryID = nil }
        }
        .onChange(of: model.shelfFocus) { _, focus in searchFocused = focus == .search; cardsFocused = focus == .cards }
        .onChange(of: searchFocused) { _, focused in if focused { model.shelfFocus = .search } }
        .onAppear { searchFocused = true }
        .alert(L("操作未完成"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("知道了")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MascotView(size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Clipori").font(.system(size: 19, weight: .bold, design: .rounded)).tracking(-0.5)
                Text(L("留住每一闪灵感")).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).tracking(1.6)
            }
            Spacer(minLength: 16)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索记忆，或问问 AI…"), text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityIdentifier("memory-search")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help(L("清空搜索"))
                }
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(scheme == .dark ? 0.055 : 0.30), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.60), lineWidth: 0.75))
                .frame(maxWidth: 340)
            Button { model.isSearchingAI ? model.cancelAI() : model.runAISearch() } label: {
                HStack(spacing: 6) {
                    if model.isSearchingAI { ProgressView().controlSize(.mini) } else { Image(systemName: "sparkles") }
                    Text(model.isSearchingAI ? L("停止") : L("AI 找回")).font(.system(size: 12, weight: .semibold))
                }.foregroundStyle(Color.clipori)
            }.buttonStyle(QuietButton(selected: true)).help(model.preferences.shortcuts[.aiSearch].display).accessibilityIdentifier("ai-search")
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 22).padding(.horizontal, 3)
            Button { model.onEdit?(nil) } label: { Image(systemName: "plus").font(.system(size: 14, weight: .medium)) }.buttonStyle(QuietButton()).help(model.preferences.shortcuts[.newMemory].display).accessibilityIdentifier("new-memory")
            Button { model.onSettings?() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 14)) }.buttonStyle(QuietButton()).help(model.preferences.shortcuts[.settings].display).accessibilityIdentifier("settings")
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryPill(name: L("全部记忆"), symbol: "square.stack.3d.up", color: .clipori, id: nil)
                    ForEach(model.categories) { category in
                        categoryPill(name: category.displayName, symbol: category.isPinboard ? "pin.fill" : nil, color: .category(category.color), id: category.id)
                    }
                }
            }.frame(height: 30)
            Spacer(minLength: 8)
            if model.pendingIncoming > 0 {
                Button { model.showIncoming() } label: { Label(LF("%d 条新记忆", model.pendingIncoming), systemImage: "arrow.clockwise").font(.system(size: 11)) }.buttonStyle(QuietButton(selected: true))
            } else {
                Text(model.aiResults != nil ? L("AI 搜索结果") : !model.query.isEmpty ? LF("%d 条结果", model.memories.count) : LF("%d 条记忆", model.totalCount))
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
    }
    private func categoryPill(name: String, symbol: String?, color: Color, id: UUID?) -> some View {
        let active = model.categoryID == id
        let targeted = id != nil && dropCategoryID == id
        let selectCategory = { withAnimation(animation) { model.categoryID = id } }
        return Button(action: selectCategory) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
                else { Circle().fill(color).frame(width: 6, height: 6) }
                Text(name).font(.system(size: 12, weight: active ? .semibold : .regular))
            }.padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .background {
                    if active { RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.075)).matchedGeometryEffect(id: "category", in: categoryAnimation) }
                }
                .background(targeted ? color.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(targeted ? color : .clear, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(active ? [.isSelected] : [])
            .scaleEffect(targeted && model.motion ? 1.04 : 1)
            .animation(model.motion ? .spring(response: 0.24, dampingFraction: 0.72) : nil, value: targeted)
            .overlay {
                CategoryDropTarget(categoryID: id, model: model, onClick: selectCategory) { inside in
                    if inside { dropCategoryID = id }
                    else if dropCategoryID == id { dropCategoryID = nil }
                }
            }
    }
    @ViewBuilder private var cards: some View {
        if model.displayed.isEmpty {
            HStack(spacing: 26) {
                MascotView(size: 94).rotationEffect(.degrees(-5))
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.query.isEmpty ? L("你的记忆，从一次复制开始。") : L("这段记忆，藏在哪里呢？")).font(.system(size: 22, weight: .medium, design: .rounded))
                    Text(model.query.isEmpty ? L("复制文字或链接，我会替你留好。\n也可以写下此刻的小小灵感。") : L("换个关键词，或让 AI 帮你找回。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                    Button { model.query.isEmpty ? model.onEdit?(nil) : model.runAISearch() } label: {
                        Label(model.query.isEmpty ? L("写下第一条备忘") : L("让 AI 找找看"), systemImage: model.query.isEmpty ? "square.and.pencil" : "sparkles")
                    }.buttonStyle(QuietButton(selected: true)).foregroundStyle(Color.clipori).padding(.top, 3)
                }
            }.frame(maxWidth: .infinity).frame(height: 233)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(model.displayed.enumerated()), id: \.element.id) { index, record in
                            MemoryCard(record: record, store: model.store, category: model.categories.first { $0.id == record.categoryID }, selected: model.selectionIDs.contains(record.id), index: index, motion: model.motion, hover: hoveredCardID == record.id, onSelect: { modifiers in
                                model.selectFromPointer(record.id, modifiers: modifiers)
                            }, onClick: { modifiers in
                                model.clickCard(record.id, modifiers: modifiers)
                            }, onActivate: {
                                model.select(record.id, reveal: false)
                                model.paste(record)
                            }, onHoverChange: { inside in
                                if inside && model.memoryDrag == nil {
                                    if hoveredCardID != record.id { hoveredCardID = record.id }
                                } else if hoveredCardID == record.id {
                                    hoveredCardID = nil
                                }
                            }, onBeginDrag: { model.beginDragging(record.id) }, onEndDrag: { model.endDragging() })
                                .contextMenu { cardMenu(record) }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(record.displayTitle)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(model.selectionIDs.contains(record.id) ? [.isSelected] : [])
                                .accessibilityAction { model.clickCard(record.id) }
                                .accessibilityAction(named: Text(L("切换多选"))) { model.selectFromPointer(record.id, modifiers: .command) }
                                .accessibilityAction(named: Text(L("粘贴到原应用"))) { model.onPaste?(record) }
                                .accessibilityAction(named: Text(L("预览"))) { model.onPreview?(record) }
                                .transition(.opacity.combined(with: .offset(y: 5)))
                                .id(record.id)
                                .onAppear { if record.id == model.memories.last?.id { Task { await model.loadMore() } } }
                                .onDisappear { if hoveredCardID == record.id { hoveredCardID = nil } }
                        }
                    }.padding(.horizontal, 22).padding(.vertical, 10)
                        .animation(model.motion ? .smooth(duration: 0.22) : nil, value: model.displayed.map(\.id))
                }.frame(height: 253)
                    .onChange(of: model.selectionToReveal) { _, id in
                        if let id { withAnimation(animation) { proxy.scrollTo(id, anchor: .center) } }
                    }
            }
        }
    }
    @ViewBuilder private func cardMenu(_ record: Memory) -> some View {
        Button(L("粘贴到原应用")) { model.onPaste?(record) }
        Button(L("复制所选内容")) { model.onCopy?(record) }
        Button(L("预览")) { model.onPreview?(record) }
        Button(L("编辑 / 追加内容")) { model.onEdit?(record) }
        Button(L("显示为桌面便笺")) { model.onSticky?(record) }
        Divider()
        Menu(model.selectionIDs.contains(record.id) && model.selectionIDs.count > 1 ? LF("将 %d 条记忆移到分类", model.selectionIDs.count) : L("移动到分类")) {
            Button(L("未分类")) { model.assign(record, to: nil) }
            ForEach(model.categories) { category in Button(category.displayName) { model.assign(record, to: category.id) } }
        }
        Button(record.keepForever ? L("取消固定") : L("固定记录（永久保留）")) { model.toggleProtected(record) }
        Divider()
        Button(L("删除记录"), role: .destructive) { model.delete(record) }
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(model.preferences.capturePaused ? Color.orange : Color.category("mint")).frame(width: 5, height: 5)
            Text(model.selectionIDs.count > 1 ? LF("已选 %d 条 · 拖到分类", model.selectionIDs.count) : model.demo ? L("预览空间 · 示例内容") : model.preferences.capturePaused ? L("记录已暂停") : L("正在悄悄记住")).font(.system(size: 10)).foregroundStyle(.secondary)
            if let notice = model.notice { Text("·  " + notice).font(.system(size: 10)).foregroundStyle(Color.clipori).lineLimit(1) }
            Spacer(minLength: 8)
            HStack(spacing: 4) { KeyHint(key: model.preferences.shortcuts[.previous].display + " " + model.preferences.shortcuts[.next].display); Text(L("选择")); KeyHint(key: model.preferences.shortcuts[.paste].display); Text(L("粘贴")); KeyHint(key: model.preferences.shortcuts[.edit].display); Text(L("编辑")); KeyHint(key: model.preferences.shortcuts[.dismiss].display); Text(L("收起")) }
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

private struct MemoryCard: View {
    let record: Memory
    let store: MemoryStore
    let category: MemoryCategory?
    let selected: Bool
    let index: Int
    let motion: Bool
    let hover: Bool
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onActivate: () -> Void
    let onHoverChange: (Bool) -> Void
    let onBeginDrag: () -> MemoryDrag?
    let onEndDrag: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var tint: Color { .category(category?.color ?? "lavender") }
    private var symbol: String {
        if record.kind == .image { return "photo" }
        if record.kind == .link { return "link" }
        return record.source == "Xcode" || category?.id == MemoryCategory.defaults[3].id ? "chevron.left.forwardslash.chevron.right" : "text.alignleft"
    }
    private var borderColor: Color {
        if selected { return tint.opacity(0.72) }
        return .white.opacity(scheme == .dark ? (hover ? 0.28 : 0.13) : (hover ? 0.85 : 0.65))
    }
    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(scheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.24))
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [.white.opacity(hover ? 0.12 : 0.075), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 16).fill(tint.opacity(selected ? 0.045 : 0.018))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 27).background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .help(L("图标表示内容类型，颜色跟随分类；可在设置中修改分类颜色。"))
                Text(record.displaySource).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Spacer()
                if record.keepForever { Image(systemName: "pin.fill").font(.system(size: 10)).help(L("已固定")) }
                Text(String(format: "%02d", index + 1)).font(.system(size: 10, weight: .medium, design: .monospaced)).opacity(0.5)
            }.foregroundStyle(tint).padding(.bottom, 13)
            if record.kind == .image {
                Text(record.displayTitle).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1).padding(.bottom, 6)
                MemoryImageView(record: record, store: store).frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        if let size = record.imageSize {
                            Text("\(size.width) × \(size.height)").font(.system(size: 8, design: .monospaced))
                                .padding(4).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4)).padding(4)
                        }
                    }
            } else {
                Text(record.displayTitle).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(2).lineSpacing(3).padding(.bottom, 9)
                Text(String(record.body.prefix(600))).font(.system(size: 12, design: category?.id == MemoryCategory.defaults[3].id ? .monospaced : .default))
                    .foregroundStyle(.secondary).lineSpacing(4).lineLimit(5).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Spacer(minLength: 8)
            HStack {
                Text(category?.displayName ?? L("未分类")).font(.system(size: 9, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.11), in: Capsule()).foregroundStyle(tint)
                Spacer()
                Text(record.createdAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.padding(16).frame(width: 237, height: 233)
            .background(glassBackground)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(borderColor, lineWidth: selected ? 1.2 : 0.65))
            .shadow(color: Color.black.opacity(scheme == .dark ? (hover ? 0.11 : 0.06) : (hover ? 0.07 : 0.035)), radius: hover ? 10 : 6, y: hover ? 5 : 3)
            .scaleEffect(hover && motion ? 1.018 : 1)
            .offset(y: hover && motion ? -6 : 0)
            .animation(motion ? .spring(response: hover ? 0.28 : 0.24, dampingFraction: hover ? 0.64 : 0.86) : nil, value: hover)
            .animation(motion ? .easeOut(duration: 0.14) : nil, value: selected)
            // Only the drawing moves; the native tracking/click region stays in place.
            .overlay {
                CardPointerInput(onSelect: onSelect, onClick: onClick, onActivate: onActivate, onHoverChange: onHoverChange, onBeginDrag: onBeginDrag, onEndDrag: onEndDrag)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(record.displayTitle + ", " + (category?.displayName ?? L("未分类")))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
