import SwiftUI

// MARK: - 通用歌谱集合页（标签 / 收藏）
struct SongCollectionView: View {
    let title: String
    var tagID: String? = nil
    var favoritesOnly = false

    @EnvironmentObject private var store: AppStore
    @State private var isGrid = false
    @State private var detail: DetailTarget? = nil

    private var list: [Song] {
        if favoritesOnly { return store.favorites() }
        if let tagID { return store.taggedSongs(tagID) }
        return []
    }

    var body: some View {
        let songs = list
        Group {
            if songs.isEmpty {
                EmptyHint(icon: "tray", title: "这里还没有歌谱", message: "在歌谱详情页勾选标签，或在首页长按选择后批量添加。")
            } else if isGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 16) {
                        ForEach(songs) { song in
                            Button { open(song, scope: songs) } label: { SongGridCell(song: song) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            Button { open(song, scope: songs) } label: { SongRow(song: song) }
                                .buttonStyle(.plain)
                            Divider().padding(.leading, 72)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isGrid.toggle()
                } label: {
                    Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .fullScreenCover(item: $detail) { target in
            DetailView(scope: target.scope, initialID: target.id).environmentObject(store)
        }
    }

    private func open(_ song: Song, scope: [Song]) {
        detail = DetailTarget(id: song.id, scope: scope.map { $0.id })
    }
}

// MARK: - 浏览记录
struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var detail: DetailTarget? = nil
    @State private var showClearConfirm = false

    private var entries: [Song] { store.historySongs() }

    var body: some View {
        NavigationView {
            Group {
                if entries.isEmpty {
                    EmptyHint(icon: "clock", title: "暂无浏览记录", message: "打开过的歌谱会按最近浏览时间倒序出现在这里。")
                } else {
                    List {
                        ForEach(entries) { song in
                            Button {
                                detail = DetailTarget(id: song.id, scope: entries.map { $0.id })
                            } label: {
                                HStack(spacing: 12) {
                                    SongThumb(songID: song.id).frame(width: 44, height: 56)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(song.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                        Text(openedText(song.id)).font(.system(size: 12)).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.removeHistory([song.id])
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("浏览记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { showClearConfirm = true }
                        .disabled(entries.isEmpty)
                }
            }
            .alert("清空全部浏览记录？", isPresented: $showClearConfirm) {
                Button("清空", role: .destructive) { store.clearHistory() }
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(item: $detail) { target in
                DetailView(scope: target.scope, initialID: target.id).environmentObject(store)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func openedText(_ id: String) -> String {
        let ts = store.history.first(where: { $0.id == id })?.openedAt ?? 0
        return Fmt.time(ts)
    }
}

// MARK: - 标签页
struct TagsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false
    @State private var renameTarget: SongTag? = nil

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: SongCollectionView(title: "收藏", favoritesOnly: true)) {
                        HStack {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            Text("收藏")
                            Spacer()
                            Text("\(store.favorites().count)").foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("系统标签")
                }

                Section {
                    ForEach(store.tags) { tag in
                        NavigationLink(destination: SongCollectionView(title: tag.name, tagID: tag.id)) {
                            HStack {
                                Image(systemName: "tag").foregroundColor(.accentColor)
                                Text(tag.name)
                                Spacer()
                                Text("\(count(tag.id))").foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.deleteTag(tag.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = tag
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    if store.tags.isEmpty {
                        Text("点右上角 + 新建标签").foregroundColor(.secondary).font(.system(size: 14))
                    }
                } header: {
                    Text("自定义标签")
                }
            }
            .navigationTitle("标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                TagNameSheet(heading: "新建标签") { name in
                    _ = store.addTag(named: name)
                }
            }
            .sheet(item: $renameTarget) { tag in
                TagNameSheet(heading: "重命名标签", initial: tag.name) { name in
                    store.renameTag(tag.id, to: name)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func count(_ tagID: String) -> Int {
        store.songs.filter { !$0.inTrash && $0.tags.contains(tagID) }.count
    }
}
