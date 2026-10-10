import SwiftUI
import CliporiCore

struct MobileEditor: View {
    @StateObject var editor: MemoryEditor
    let categories: [MemoryCategory]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var closing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                TextField(L("给这段记忆起个名字"), text: $editor.record.title)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .onChange(of: editor.record.title) { _, _ in editor.changed() }
                TextEditor(text: $editor.record.body).font(.body).lineSpacing(6).scrollContentBackground(.hidden)
                    .onChange(of: editor.record.body) { _, _ in editor.changed() }
                    .overlay(alignment: .topLeading) {
                        if editor.record.body.isEmpty { Text(L("写下灵感，或粘贴一段想留住的内容…")).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                    }
                    .accessibilityLabel(L("备忘正文"))
                Picker(L("分类"), selection: Binding(get: { editor.record.categoryID }, set: { editor.assign($0) })) {
                    Text(L("未分类")).tag(nil as UUID?)
                    ForEach(categories) { Text($0.displayName).tag(Optional($0.id)) }
                }
                Toggle(L("固定这条记录"), isOn: $editor.record.keepForever).font(.subheadline)
                    .onChange(of: editor.record.keepForever) { _, _ in editor.changed() }
                Text(L(editor.saveState)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            }.padding(22).navigationTitle(L("写下这一刻")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("完成")) { closing = true; Task { if await editor.flush() { dismiss() }; closing = false } }.disabled(closing)
                    }
                }
        }.interactiveDismissDisabled().tint(.clipori)
            .onChange(of: phase) { _, value in if value != .active { Task { await editor.flush() } } }
    }
}
