import SwiftUI
import CliporiCore

/// Each row owns its edit draft; the creation form has separate state.
struct CategorySettingsRow: View {
    let category: MemoryCategory
    let save: (MemoryCategory) async throws -> Void
    let delete: () async throws -> Void
    let reportError: (Error) -> Void
    @State private var draft: MemoryCategory
    @State private var editing = false
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    init(category: MemoryCategory, save: @escaping (MemoryCategory) async throws -> Void,
         delete: @escaping () async throws -> Void, reportError: @escaping (Error) -> Void) {
        self.category = category; self.save = save; self.delete = delete; self.reportError = reportError
        _draft = State(initialValue: category)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11))
                .foregroundStyle(.tertiary).help(L("拖动调整顺序"))
            if editing {
                CategoryColorPicker(selection: $draft.color, compact: true)
                TextField(L("分类名称"), text: $draft.name).textFieldStyle(.roundedBorder)
                    .focused($nameFocused).onSubmit { saveDraft() }
                    .onExitCommand { if !saving { editing = false } }
                    .accessibilityIdentifier("category-name-\(category.id)")
                Button { draft.isPinboard.toggle() } label: {
                    Image(systemName: draft.isPinboard ? "pin.fill" : "pin")
                        .foregroundStyle(draft.isPinboard ? Color.clipori : Color.secondary)
                }.help(L("固定分类（Pinboard）· 其中记录不自动清理"))
                    .accessibilityLabel(L("固定分类"))
                    .accessibilityValue(draft.isPinboard ? L("已固定") : L("未固定"))
                Button { editing = false } label: { Image(systemName: "xmark") }
                    .help(L("取消")).accessibilityLabel(L("取消"))
                Button { saveDraft() } label: { Image(systemName: "checkmark").foregroundStyle(Color.clipori) }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(L("保存分类")).accessibilityLabel(L("保存分类"))
            } else {
                Image(systemName: category.isPinboard ? "pin.fill" : "tag").font(.system(size: 16))
                    .foregroundStyle(Color.category(category.color))
                Text(category.displayName).lineLimit(1)
                Spacer()
                Button(L("编辑")) { draft = category; editing = true; nameFocused = true }
                    .accessibilityIdentifier("edit-category-\(category.id)")
                Button {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await delete() } catch { reportError(error) }
                    }
                } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                    .help(L("删除分类，记录会移入未分类")).accessibilityLabel(L("删除"))
            }
        }.buttonStyle(.borderless).disabled(saving)
            .padding(.vertical, 6).contentShape(Rectangle())
            .moveDisabled(editing || saving)
            .accessibilityElement(children: .contain)
    }

    private func saveDraft() {
        guard !saving else { return }
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { return }
        value.modifiedAt = Date()
        saving = true
        Task {
            defer { saving = false }
            do { try await save(value); editing = false }
            catch { reportError(error) }
        }
    }
}

