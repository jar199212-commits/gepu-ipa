import SwiftUI

// MARK: - 首页
struct HomeView: View {
    @EnvironmentObject private var store: AppStore

    @State private var isGrid = false
    @State private var query = ""
    @State private var resultIDs: [String]? = nil
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var detail: DetailTarget? = nil
    @State private var showSync = false
    @State private var showAddTag = false
    @State private var showRemoveTag = false
    @State private var showDeleteConfirm = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationView {
            content
                .navigationTitle("歌谱")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) {
                    if isSelecting { batchBar }
                }
                .sheet(isPresented: $showSync) {
                    SyncSheet().environmentObject(store)
                }
                .sheet(isPresented: $showAddTag) {
                    BatchTagSheet(mode: .add, ids: Array(selection)).environmentObject(store)
                }
                .sheet(isPresented: $showRemoveTag) {
                    BatchTagSheet(mode: .remove, ids: Array(selection)).environmentObject(store)
                }
                .fullScreenCover(item: $detail) { target in
                    DetailView(scope: target.scope, initialID: target.id)
                        .environmentObject(store)
                }
                .alert(isPresented: $showDeleteConfirm) {
                    Alert(
                        title: Text("删除歌谱"),
                        message: Text("将从首页移入回收站，共 \(selection.count) 首，可在「我的 → 回收站」恢复。"),
                        primaryButton: .destructive(Text("移入回收站")) {
                            store.moveToTrash(Array(selection))
                            selection.removeAll()
                            isSelecting = false
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        let list = displayedSongs
        VStack(spacing: 0) {
            searchHeader
            if list.isEmpty {
                emptyState
            } else {
                if isGrid { gridView(list) } else { listView(list) }
            }
        }
    }

    private var displayedSongs: [Song] {
        if let ids = resultIDs { return store.resolve(ids) }
        return store.activeSongs()
    }

    private var searchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索歌名 / 谱面文字 / 拼音首字母", text: $query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit { store.addSearchHistory(query) }
                if !query.isEmpty {
                    Button {
                        query = ""
                        resultIDs = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if query.isEmpty && !store.searchHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.searchHistory, id: \.self) { keyword in
                            Button {
                                query = keyword
                            } label: {
                                TagChip(text: keyword, tint: .secondary)
                            }
                        }
                        Button {
                            store.clearSearchHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.bottom, 6)
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                resultIDs = nil
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                let ids = store.searchSongs(trimmed)
                if Task.isCancelled { return }
                resultIDs = ids
            }
        }
    }

    private var emptyState: some View {
        Group {
            if query.isEmpty {
                EmptyHint(
                    icon: "music.note.list",
                    title: "还没有歌谱",
                    message: "先在 NAS 上部署好 WebDAV 目录并运行索引脚本，然后在设置里填写地址并同步。",
                    actionTitle: "打开同步",
                    action: { showSync = true }
                )
            } else {
                EmptyHint(icon: "magnifyingglass", title: "没有匹配的歌谱", message: "试试歌名片段、拼音首字母，或谱面上出现过的词。")
            }
        }
    }

    private func gridView(_ list: [Song]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 16) {
                ForEach(list) { song in
                    cellContainer(song: song, scope: list)
                }
            }
            .padding(12)
        }
    }

    private func listView(_ list: [Song]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list) { song in
                    cellContainer(song: song, scope: list)
                    Divider().padding(.leading, 72)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func cellContainer(song: Song, scope: [Song]) -> some View {
        Button {
            handleTap(song, scope: scope)
        } label: {
            ZStack(alignment: .topLeading) {
                if isGrid {
                    SongGridCell(song: song)
                } else {
                    SongRow(song: song, showFavoriteButton: !isSelecting)
                }
                if isSelecting {
                    Image(systemName: selection.contains(song.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(selection.contains(song.id) ? .accentColor : .secondary)
                        .padding(6)
                        .background(Color(UIColor.systemBackground).clipShape(Circle()).opacity(0.85))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func handleTap(_ song: Song, scope: [Song]) {
        if isSelecting {
            if selection.contains(song.id) { selection.remove(song.id) } else { selection.insert(song.id) }
            return
        }
        if !query.isEmpty { store.addSearchHistory(query) }
        let ids = scope.map { $0.id }
        detail = DetailTarget(id: song.id, scope: ids)
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                isGrid.toggle()
            } label: {
                Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
            }
            Button(isSelecting ? "完成" : "选择") {
                isSelecting.toggle()
                if !isSelecting { selection.removeAll() }
            }
            Button {
                showSync = true
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var batchBar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selection.count) 首")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Button("加标签") { showAddTag = true }
                .disabled(selection.isEmpty)
            Button("移标签") { showRemoveTag = true }
                .disabled(selection.isEmpty)
            Button("删除") { showDeleteConfirm = true }
                .foregroundColor(.red)
                .disabled(selection.isEmpty)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
