import SwiftUI
import UniformTypeIdentifiers

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - 我的
struct MeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var stats = LibraryStats()

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(alignment: .center, spacing: 0) {
                        stat("歌谱", "\(stats.total)")
                        stat("收藏", "\(stats.favorites)")
                        stat("回收站", "\(stats.trashed)")
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    NavigationLink(destination: TrashView()) {
                        HStack {
                            Label("回收站", systemImage: "trash")
                            Spacer()
                            if stats.trashed > 0 {
                                Text("\(stats.trashed)")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundColor(.red)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    NavigationLink(destination: SettingsView()) {
                        Label("设置", systemImage: "gearshape")
                    }
                    NavigationLink(destination: SyncLogView()) {
                        Label("同步日志", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section {
                    HStack {
                        Text("缩略图缓存")
                        Spacer()
                        Text("\(stats.thumbs) 张").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("原图缓存")
                        Spacer()
                        Text(Fmt.bytes(stats.cacheBytes)).foregroundColor(.secondary)
                    }
                } header: {
                    Text("本地缓存")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    Text("歌谱 · NAS 版：歌谱原图全部存放在你自建的 NAS WebDAV 目录，App 只保存索引、缩略图与按需下载的原图。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { stats = store.stats() }
        }
        .navigationViewStyle(.stack)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold))
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 回收站
struct TrashView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingPurge: Song? = nil
    @State private var showEmptyAll = false

    private var items: [Song] { store.trashedSongs() }

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    Text("回收站是空的").foregroundColor(.secondary)
                }
                ForEach(items) { song in
                    HStack(spacing: 12) {
                        SongThumb(songID: song.id).frame(width: 44, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            Text("删除于 \(Fmt.time(song.deletedAt ?? 0))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            store.restore([song.id])
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingPurge = song
                        } label: {
                            Label("彻底删除", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("回收站保留 \(store.settings.trashDays) 天，超期自动清理。彻底删除并执行同步后，NAS 上的原图、缩略图、OCR 与元数据会一并删除，且不会再次拉取。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空") { showEmptyAll = true }
                    .disabled(items.isEmpty)
            }
        }
        .alert("清空回收站？", isPresented: $showEmptyAll) {
            Button("全部彻底删除", role: .destructive) {
                store.purge(items.map { $0.id })
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("共 \(items.count) 首。彻底删除后无法恢复，同步时会同时删除 NAS 上的原图。")
        }
        .confirmationDialog("彻底删除这首歌谱？", isPresented: Binding(
            get: { pendingPurge != nil },
            set: { if !$0 { pendingPurge = nil } }
        ), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) {
                if let song = pendingPurge { store.purge([song.id]) }
                pendingPurge = nil
            }
            Button("取消", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("本地文件会立即删除；NAS 上的原图在下次同步时删除，之后不会再被拉回。")
        }
    }
}

// MARK: - 同步日志
struct SyncLogView: View {
    @State private var text = ""
    @State private var share: ShareItem? = nil
    @State private var showClear = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .navigationTitle("同步日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("同步日志.txt")
                    try? LogFile.read().write(to: url, atomically: true, encoding: .utf8)
                    share = ShareItem(url: url)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button("清空") { showClear = true }
            }
        }
        .alert("清空同步日志？", isPresented: $showClear) {
            Button("清空", role: .destructive) {
                LogFile.clear()
                text = LogFile.read()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear { text = LogFile.read() }
    }
}

// MARK: - 设置
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var testing = false
    @State private var testResult: String? = nil
    @State private var showSync = false
    @State private var showImporter = false
    @State private var shareItem: ShareItem? = nil
    @State private var importMessage: String? = nil
    @State private var cacheText = "计算中…"
    @State private var thumbText = "—"

    var body: some View {
        Form {
            Section {
                TextField("http://[2408:xxxx::1]:5005/", text: $store.settings.baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                TextField("账号（无认证可留空）", text: $store.settings.username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                SecureField("密码（无认证可留空）", text: $store.settings.password)

                Toggle("仅在 IPv6 网络下同步", isOn: $store.settings.onlyIPv6)
                Toggle("拉取 OCR 文本（支持按谱面文字搜索）", isOn: $store.settings.downloadOCR)

                Button {
                    runTest()
                } label: {
                    HStack {
                        Text("测试连通性")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }

                if let testResult {
                    Text(testResult)
                        .font(.system(size: 12))
                        .foregroundColor(testResult.hasPrefix("连接成功") ? .green : .red)
                }

                Button("立即同步") { showSync = true }
            } header: {
                Text("NAS 同步")
            } footer: {
                Text("地址填 WebDAV 根目录（index.json 所在目录），例如 http://[2408:abcd::12]:5005/。开启「仅 IPv6」后，域名必须能解析出 AAAA 记录。")
            }

            Section {
                Stepper("原图缓存上限 \(store.settings.cacheLimitMB) MB",
                        value: $store.settings.cacheLimitMB, in: 128...20000, step: 128)
                HStack {
                    Text("已用原图缓存")
                    Spacer()
                    Text(cacheText).foregroundColor(.secondary)
                }
                HStack {
                    Text("缩略图")
                    Spacer()
                    Text(thumbText).foregroundColor(.secondary)
                }
                Button("清空原图缓存") {
                    store.clearOriginalCache()
                    refreshStorage()
                }
            } header: {
                Text("缓存")
            } footer: {
                Text("原图按需下载，超过上限时自动淘汰最久未使用的文件；缩略图与索引始终保留，可离线浏览和搜索。")
            }

            Section {
                Stepper("浏览记录最多 \(store.settings.maxHistory) 条",
                        value: $store.settings.maxHistory, in: 100...5000, step: 100)
                Stepper("回收站保留 \(store.settings.trashDays) 天",
                        value: $store.settings.trashDays, in: 0...365, step: 5)
            } header: {
                Text("浏览记录与回收站")
            } footer: {
                Text(store.settings.trashDays == 0 ? "0 天表示不自动清理。" : "超过保留天数的回收站歌谱会在启动时自动彻底删除。")
            }

            Section("外观") {
                Picker("模式", selection: $store.settings.appearance) {
                    Text("跟随系统").tag("system")
                    Text("亮色").tag("light")
                    Text("暗色").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("导出备份文件") {
                    if let url = store.exportBackup() {
                        shareItem = ShareItem(url: url)
                    }
                }
                Button("从备份文件恢复") { showImporter = true }
                if let importMessage {
                    Text(importMessage).font(.system(size: 12)).foregroundColor(.secondary)
                }
            } header: {
                Text("数据")
            } footer: {
                Text("备份包含歌名、标签、收藏、笔记与浏览记录，不含图片本体。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshStorage() }
        .onDisappear {
            store.saveSettings()
            store.trimHistory()
            store.evictCacheIfNeeded()
        }
        .sheet(isPresented: $showSync) {
            SyncSheet().environmentObject(store)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importMessage = store.importBackup(from: url)
                }
            case .failure(let error):
                importMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        Task {
            let text = await SyncEngine.shared.testConnection(store: store)
            testResult = text
            testing = false
        }
    }

    private func refreshStorage() {
        cacheText = Fmt.bytes(Paths.directorySize(Paths.originals))
        let count = (try? FileManager.default.contentsOfDirectory(atPath: Paths.thumbs.path).count) ?? 0
        thumbText = "\(count) 张"
    }
}
