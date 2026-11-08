import SwiftUI

// MARK: - 歌谱详情（全屏看图 + 左右滑动）
struct DetailView: View {
    let scope: [String]

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var chrome = true
    @State private var showRename = false
    @State private var showNote = false
    @State private var showTags = false
    @State private var showDeleteConfirm = false

    init(scope: [String], initialID: String) {
        self.scope = scope
        let start = scope.firstIndex(of: initialID) ?? 0
        _index = State(initialValue: max(0, start))
    }

    private var currentID: String? {
        guard scope.indices.contains(index) else { return nil }
        return scope[index]
    }

    private var current: Song? {
        guard let id = currentID else { return nil }
        return store.song(id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ImagePager(
                ids: scope,
                index: $index,
                loader: { id in await ImageLoader.original(id: id, store: store) },
                onTap: {
                    withAnimation(.easeInOut(duration: 0.18)) { chrome.toggle() }
                }
            )
            .ignoresSafeArea()

            if chrome {
                chromeLayer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let id = currentID { store.recordOpen(id) }
        }
        .onChange(of: index) { _ in
            if let id = currentID { store.recordOpen(id) }
        }
        .sheet(isPresented: $showRename) {
            if let id = currentID {
                RenameSheet(songID: id, currentTitle: current?.title ?? "")
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showNote) {
            if let id = currentID {
                NoteSheet(songID: id, currentNote: current?.note ?? "")
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showTags) {
            if let id = currentID {
                TagEditorSheet(songID: id).environmentObject(store)
            }
        }
        .confirmationDialog("删除这首歌谱？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("移入回收站", role: .destructive) {
                if let id = currentID {
                    store.moveToTrash([id])
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移入回收站后可从「我的 → 回收站」恢复；彻底删除并同步后，NAS 上的原图也会被删除。")
        }
    }

    // MARK: 覆盖层

    private var chromeLayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }

                Spacer()

                Text(current?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    if let id = currentID { store.toggleFavorite(id) }
                } label: {
                    Image(systemName: (current?.favorite ?? false) ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .foregroundColor((current?.favorite ?? false) ? .yellow : .white)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(current?.title ?? "")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer()
                    Text("\(index + 1)/\(scope.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                if let song = current, !song.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(song.tags, id: \.self) { tagID in
                                TagChip(text: store.tagName(tagID), tint: .white)
                            }
                        }
                    }
                }

                if let song = current, !song.note.isEmpty {
                    Text(song.note)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(2)
                }

                HStack(spacing: 0) {
                    actionButton("笔记", "note.text") { showNote = true }
                    actionButton("标签", "tag") { showTags = true }
                    actionButton("改名", "pencil") { showRename = true }
                    actionButton("删除", "trash", tint: .red) { showDeleteConfirm = true }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func actionButton(_ title: String, _ icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.system(size: 12))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
