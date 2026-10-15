import SwiftUI
import CliporiCore

typealias EditorModel = MemoryEditor
extension MemoryEditor {
    convenience init(record: Memory?, app: AppModel) {
        self.init(record: record, store: app.store) { [weak app] in
            app?.cancelAI(); await app?.reload()
        }
    }
}

struct EditorView: View {
    @StateObject var editor: EditorModel
    @ObservedObject var app: AppModel
    var sticky = false
    var focusTitle = false
    var onPin: ((Bool) -> Void)?
    @State private var pinned = true
    @FocusState private var editing: Bool
    @FocusState private var titleEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil").foregroundStyle(Color.clipori)
                Text(sticky ? L("桌面便笺") : L("写下这一刻")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if sticky {
                    Button { pinned.toggle(); onPin?(pinned) } label: { Image(systemName: pinned ? "pin.fill" : "pin") }.buttonStyle(.plain).help(L("窗口置顶"))
                }
                Text(L(editor.saveState)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.padding(20)
            TextField(L("给这段记忆起个名字"), text: $editor.record.title)
                .focused($titleEditing)
                .textFieldStyle(.plain).font(.system(size: 23, weight: .semibold, design: .rounded)).padding(.horizontal, 22).padding(.bottom, 16)
                .onChange(of: editor.record.title) { _, _ in editor.changed() }.accessibilityIdentifier("editor-title")
            if editor.record.kind == .image {
                MemoryImageView(record: editor.record, store: app.store, maxPixelSize: 1024)
                    .frame(height: sticky ? 90 : 150).padding(.horizontal, 22).padding(.bottom, 10)
                Text(L("图片备注（参与搜索）")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 6)
            }
            TextEditor(text: $editor.record.body).font(.system(size: 14)).lineSpacing(6).scrollContentBackground(.hidden)
                .padding(.horizontal, 18).focused($editing)
                .onChange(of: editor.record.body) { _, _ in editor.changed() }.accessibilityIdentifier("editor-body")
            Divider().padding(.top, 12)
            HStack(spacing: 10) {
                Menu {
                    Button(L("未分类")) { editor.assign(nil) }
                    ForEach(app.categories) { category in Button(category.displayName) { editor.assign(category.id) } }
                } label: {
                    Label(app.categories.first { $0.id == editor.record.categoryID }?.displayName ?? L("未分类"), systemImage: "tag")
                }.menuStyle(.borderlessButton).frame(width: 100)
                Spacer()
                Toggle(L("固定这条记录"), isOn: $editor.record.keepForever).toggleStyle(.checkbox).font(.system(size: 11))
                    .onChange(of: editor.record.keepForever) { _, _ in editor.changed() }
            }.padding(18)
        }.background(.background)
            .id(app.preferences.language)
            .environment(\.locale, L10n.locale)
            .onAppear { if focusTitle { titleEditing = true } else { editing = true } }
            .onDisappear { Task { await editor.flush() } }
    }
}
