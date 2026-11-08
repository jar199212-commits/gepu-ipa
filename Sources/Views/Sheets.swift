import SwiftUI

// MARK: - 改名
struct RenameSheet: View {
    let songID: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(songID: String, currentTitle: String) {
        self.songID = songID
        _text = State(initialValue: currentTitle)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("歌名", text: $text)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("新歌名会跟随歌谱 ID 写入 NAS 的 meta/<id>.json，不会产生重复条目。")
                }
            }
            .navigationTitle("修改歌名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.rename(songID, to: text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 笔记
struct NoteSheet: View {
    let songID: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(songID: String, currentNote: String) {
        self.songID = songID
        _text = State(initialValue: currentNote)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("笔记只属于这首歌（按 ID 绑定），保存在本地，并在同步时写入 NAS 的 meta/<id>.json。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .navigationTitle("专属笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.setNote(songID, text)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 单曲标签编辑
struct TagEditorSheet: View {
    let songID: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(store.tags) { tag in
                        Button {
                            store.toggleTag(tag.id, on: songID)
                        } label: {
                            HStack {
                                Text(tag.name).foregroundColor(.primary)
                                Spacer()
                                if store.song(songID)?.tags.contains(tag.id) == true {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("已绑定标签")
                } footer: {
                    Text("勾选或取消即可增删标签；收藏为系统标签，用星标控制。")
                }

                Section("新建标签") {
                    HStack {
                        TextField("标签名称", text: $newTag)
                        Button("添加") {
                            if let tag = store.addTag(named: newTag) {
                                store.addTag(tag.id, to: [songID])
                                newTag = ""
                            }
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 批量加/移标签
struct BatchTagSheet: View {
    enum Mode { case add, remove }
    let mode: Mode
    let ids: [String]

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    private var title: String { mode == .add ? "批量添加标签" : "批量移除标签" }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(store.tags) { tag in
                        Button {
                            apply(tag.id)
                        } label: {
                            HStack {
                                Text(tag.name).foregroundColor(.primary)
                                Spacer()
                                Text(mode == .add ? "添加" : "移除")
                                    .font(.system(size: 13))
                                    .foregroundColor(mode == .add ? .accentColor : .red)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if store.tags.isEmpty {
                        Text("还没有自定义标签").foregroundColor(.secondary)
                    }
                } header: {
                    Text("已选 \(ids.count) 首")
                }

                if mode == .add {
                    Section("新建标签并应用") {
                        HStack {
                            TextField("标签名称", text: $newTag)
                            Button("创建") {
                                if let tag = store.addTag(named: newTag) {
                                    apply(tag.id)
                                }
                            }
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func apply(_ tagID: String) {
        if mode == .add {
            store.addTag(tagID, to: ids)
        } else {
            store.removeTag(tagID, from: ids)
        }
        dismiss()
    }
}

// MARK: - 标签名称编辑
struct TagNameSheet: View {
    let heading: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(heading: String, initial: String = "", onSave: @escaping (String) -> Void) {
        self.heading = heading
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("标签名称", text: $text)
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
