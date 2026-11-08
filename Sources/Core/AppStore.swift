import Foundation
import SwiftUI

struct SyncMeta: Codable {
    var indexGeneratedAt: Double = 0
    var ocrVersion: String = ""
    var lastSyncAt: Double = 0
}

struct BackupBundle: Codable {
    var version: Int
    var exportedAt: Double
    var songs: [Song]
    var tags: [SongTag]
    var history: [HistoryEntry]
}

/// 全 App 唯一数据源。所有改动都通过它落到本地 JSON，界面对它做观察。
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var songs: [Song] = []
    @Published var tags: [SongTag] = []
    @Published var history: [HistoryEntry] = []
    @Published var settings = Settings()
    @Published var pendingDeletes: [String: String] = [:]
    @Published var purged: Set<String> = []
    @Published var dirty: Set<String> = []
    @Published var ocr: [String: String] = [:]
    @Published var searchHistory: [String] = []
    @Published var syncMeta = SyncMeta()
    @Published var syncProgress = SyncProgress()

    /// 界面数据版本（任何改动都自增）
    @Published var dataRevision = 0
    /// 搜索索引版本（仅歌名 / 成员 / OCR 变化时自增）
    @Published var indexRevision = 0

    let search = SearchEngine()

    private var songIndex: [String: Song] = [:]
    private var songIndexRevision = -1
    private var sortedCache: [Song] = []
    private var sortedCacheRevision = -1
    private var indexBuiltRevision = -1
    private var saveWork: DispatchWorkItem?

    // MARK: - 初始化

    init() {
        Paths.ensure(Paths.data)
        songs = JSONFile.read(Paths.file("songs.json"), as: [Song].self) ?? []
        tags = JSONFile.read(Paths.file("tags.json"), as: [SongTag].self) ?? []
        history = JSONFile.read(Paths.file("history.json"), as: [HistoryEntry].self) ?? []
        settings = JSONFile.read(Paths.file("settings.json"), as: Settings.self) ?? Settings()
        pendingDeletes = JSONFile.read(Paths.file("pending.json"), as: [String: String].self) ?? [:]
        purged = JSONFile.read(Paths.file("purged.json"), as: Set<String>.self) ?? []
        dirty = JSONFile.read(Paths.file("dirty.json"), as: Set<String>.self) ?? []
        ocr = JSONFile.read(Paths.file("ocr.json"), as: [String: String].self) ?? [:]
        searchHistory = JSONFile.read(Paths.file("searchhistory.json"), as: [String].self) ?? []
        syncMeta = JSONFile.read(Paths.file("syncmeta.json"), as: SyncMeta.self) ?? SyncMeta()

        PinyinProvider.shared.load()
        cleanupTrash(auto: true)
        evictCacheIfNeeded()
    }

    // MARK: - 读取

    private func rebuildIndexIfNeeded() {
        guard songIndexRevision != dataRevision else { return }
        var map: [String: Song] = [:]
        map.reserveCapacity(songs.count)
        for song in songs { map[song.id] = song }
        songIndex = map
        songIndexRevision = dataRevision
    }

    func song(_ id: String) -> Song? {
        rebuildIndexIfNeeded()
        return songIndex[id]
    }

    func resolve(_ ids: [String]) -> [Song] {
        rebuildIndexIfNeeded()
        return ids.compactMap { songIndex[$0] }
    }

    /// 首页数据源：未进回收站、按歌名排序（唯一排序方式）
    func activeSongs() -> [Song] {
        if sortedCacheRevision != dataRevision {
            let zh = Locale(identifier: "zh_Hans_CN")
            var list = songs.filter { !$0.inTrash }
            list.sort { a, b in
                a.title.compare(b.title, options: [.caseInsensitive, .numeric, .widthInsensitive], range: nil, locale: zh) == .orderedAscending
            }
            sortedCache = list
            sortedCacheRevision = dataRevision
        }
        return sortedCache
    }

    func trashedSongs() -> [Song] {
        songs.filter { $0.inTrash }.sorted { ($0.deletedAt ?? 0) > ($1.deletedAt ?? 0) }
    }

    func historySongs() -> [Song] {
        history.compactMap { entry in
            guard let song = song(entry.id) else { return nil }
            return song
        }
    }

    func tagName(_ id: String) -> String {
        tags.first(where: { $0.id == id })?.name ?? "已删除标签"
    }

    func taggedSongs(_ tagID: String) -> [Song] {
        let zh = Locale(identifier: "zh_Hans_CN")
        return songs.filter { !$0.inTrash && $0.tags.contains(tagID) }.sorted {
            $0.title.compare($1.title, options: [.caseInsensitive, .numeric], range: nil, locale: zh) == .orderedAscending
        }
    }

    func favorites() -> [Song] {
        let zh = Locale(identifier: "zh_Hans_CN")
        return songs.filter { !$0.inTrash && $0.favorite }.sorted {
            $0.title.compare($1.title, options: [.caseInsensitive, .numeric], range: nil, locale: zh) == .orderedAscending
        }
    }

    func stats() -> LibraryStats {
        var s = LibraryStats()
        s.total = songs.filter { !$0.inTrash }.count
        s.favorites = songs.filter { !$0.inTrash && $0.favorite }.count
        s.trashed = songs.filter { $0.inTrash }.count
        s.thumbs = (try? FileManager.default.contentsOfDirectory(atPath: Paths.thumbs.path).count) ?? 0
        s.cacheBytes = Paths.directorySize(Paths.originals)
        return s
    }

    // MARK: - 写入

    private func invalidate(index: Bool) {
        dataRevision += 1
        if index { indexRevision += 1 }
    }

    func mutate(_ id: String, index: Bool = false, _ block: (inout Song) -> Void) {
        guard let position = songs.firstIndex(where: { $0.id == id }) else { return }
        block(&songs[position])
        invalidate(index: index)
        saveSongsSoon()
    }

    func toggleFavorite(_ id: String) {
        mutate(id) { $0.favorite.toggle(); $0.updatedAt = Date().timeIntervalSince1970 }
        dirty.insert(id)
        saveDirtySoon()
    }

    func rename(_ id: String, to newTitle: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        mutate(id, index: true) {
            $0.title = title
            $0.titleOverridden = true
            $0.updatedAt = Date().timeIntervalSince1970
        }
        dirty.insert(id)
        saveDirtySoon()
    }

    func setNote(_ id: String, _ note: String) {
        mutate(id) { $0.note = note; $0.updatedAt = Date().timeIntervalSince1970 }
        dirty.insert(id)
        saveDirtySoon()
    }

    func addTag(_ tagID: String, to ids: [String]) {
        let set = Set(ids)
        for i in songs.indices where set.contains(songs[i].id) {
            if !songs[i].tags.contains(tagID) { songs[i].tags.append(tagID) }
            songs[i].updatedAt = Date().timeIntervalSince1970
            dirty.insert(songs[i].id)
        }
        invalidate(index: false)
        saveSongsSoon()
        saveDirtySoon()
    }

    func removeTag(_ tagID: String, from ids: [String]) {
        let set = Set(ids)
        for i in songs.indices where set.contains(songs[i].id) {
            songs[i].tags.removeAll { $0 == tagID }
            songs[i].updatedAt = Date().timeIntervalSince1970
            dirty.insert(songs[i].id)
        }
        invalidate(index: false)
        saveSongsSoon()
        saveDirtySoon()
    }

    func toggleTag(_ tagID: String, on id: String) {
        mutate(id) { song in
            if song.tags.contains(tagID) { song.tags.removeAll { $0 == tagID } } else { song.tags.append(tagID) }
            song.updatedAt = Date().timeIntervalSince1970
        }
        dirty.insert(id)
        saveDirtySoon()
    }

    // MARK: - 标签管理

    func addTag(named raw: String) -> SongTag? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard !tags.contains(where: { $0.name == name }) else { return nil }
        let tag = SongTag(name: name)
        tags.append(tag)
        saveTags()
        return tag
    }

    func renameTag(_ id: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[i].name = name
        saveTags()
        invalidate(index: false)
    }

    func deleteTag(_ id: String) {
        tags.removeAll { $0.id == id }
        for i in songs.indices {
            if songs[i].tags.contains(id) {
                songs[i].tags.removeAll { $0 == id }
                dirty.insert(songs[i].id)
            }
        }
        saveTags()
        saveSongsSoon()
        saveDirtySoon()
        invalidate(index: false)
    }

    // MARK: - 浏览记录

    func recordOpen(_ id: String) {
        if let i = history.firstIndex(where: { $0.id == id }) { history.remove(at: i) }
        history.insert(HistoryEntry(id: id, openedAt: Date().timeIntervalSince1970), at: 0)
        let maxCount = max(50, settings.maxHistory)
        if history.count > maxCount { history.removeLast(history.count - maxCount) }
        saveHistory()
    }

    func removeHistory(_ ids: [String]) {
        let set = Set(ids)
        history.removeAll { set.contains($0.id) }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func trimHistory() {
        guard history.count > settings.maxHistory else { return }
        history.removeLast(history.count - settings.maxHistory)
        saveHistory()
    }

    // MARK: - 删除 / 回收站

    func moveToTrash(_ ids: [String]) {
        let set = Set(ids)
        let now = Date().timeIntervalSince1970
        for i in songs.indices where set.contains(songs[i].id) {
            songs[i].inTrash = true
            songs[i].deletedAt = now
        }
        invalidate(index: true)
        saveSongs()
    }

    func restore(_ ids: [String]) {
        let set = Set(ids)
        for i in songs.indices where set.contains(songs[i].id) {
            songs[i].inTrash = false
            songs[i].deletedAt = nil
        }
        invalidate(index: true)
        saveSongs()
    }

    /// 永久删除：本地移除 + 记入待同步删除队列，下次同步联动删除 NAS 原图与元数据
    func purge(_ ids: [String]) {
        let set = Set(ids)
        for id in set {
            if let song = song(id) { pendingDeletes[id] = song.file }
            purged.insert(id)
            removeLocalFiles(id: id)
        }
        songs.removeAll { set.contains($0.id) }
        history.removeAll { set.contains($0.id) }
        dirty.subtract(set)
        invalidate(index: true)
        saveSongs()
        saveHistory()
        savePending()
        savePurged()
        saveDirtyNow()
    }

    private func removeLocalFiles(id: String) {
        try? FileManager.default.removeItem(at: Paths.thumb(id))
        if let song = song(id) {
            try? FileManager.default.removeItem(at: Paths.original(id, file: song.file))
        }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: Paths.originals.path) {
            for f in files where f.hasPrefix(id + ".") {
                try? fm.removeItem(at: Paths.originals.appendingPathComponent(f))
            }
        }
        ocr.removeValue(forKey: id)
    }

    func cleanupTrash(auto: Bool) {
        guard settings.trashDays > 0 else { return }
        let limit = Date().timeIntervalSince1970 - Double(settings.trashDays) * 86400
        let expired = songs.filter { $0.inTrash && ($0.deletedAt ?? 0) < limit }.map { $0.id }
        guard !expired.isEmpty else { return }
        purge(expired)
        if auto { LogFile.append("回收站自动清理 \(expired.count) 首（超过 \(settings.trashDays) 天）") }
    }

    // MARK: - 搜索

    var searchQueryHints: [String] { searchHistory }

    func ensureSearchIndex() {
        guard indexBuiltRevision != indexRevision else { return }
        indexBuiltRevision = indexRevision
        let snapshot = songs.filter { !$0.inTrash }.map { ($0.id, $0.title) }
        let ocrSnapshot = ocr
        let engine = search
        DispatchQueue.global(qos: .userInitiated).async {
            var docs: [SearchEngine.Doc] = []
            docs.reserveCapacity(snapshot.count)
            for (id, title) in snapshot {
                docs.append(SearchEngine.Doc(
                    id: id,
                    title: SearchEngine.normalize(title),
                    py: PinyinProvider.shared.initials(for: title),
                    ocr: SearchEngine.normalize(ocrSnapshot[id] ?? "")
                ))
            }
            DispatchQueue.main.async {
                engine.setDocs(docs)
            }
        }
    }

    func searchSongs(_ query: String) -> [Song] {
        ensureSearchIndex()
        return resolve(search.search(query))
    }

    func addSearchHistory(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count > 0 else { return }
        searchHistory.removeAll { $0 == q }
        searchHistory.insert(q, at: 0)
        if searchHistory.count > 30 { searchHistory.removeLast(searchHistory.count - 30) }
        JSONFile.write(searchHistory, to: Paths.file("searchhistory.json"))
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        JSONFile.write(searchHistory, to: Paths.file("searchhistory.json"))
    }

    // MARK: - 同步支撑

    func webdav() -> WebDAVClient? {
        guard !settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return WebDAVClient(config: WebDAVConfig(
            baseURL: settings.baseURL,
            username: settings.username,
            password: settings.password,
            onlyIPv6: settings.onlyIPv6
        ))
    }

    func markDirty(_ id: String) {
        dirty.insert(id)
        saveDirtySoon()
    }

    func thumbURL(_ id: String) -> URL { Paths.thumb(id) }

    /// 把 NAS 索引合并进本地库。新增与更新一次完成，只在末尾刷新一次缓存。
    @discardableResult
    func applyRemoteUpdate(_ items: [RemoteItem]) -> (added: Int, updated: Int) {
        var positions: [String: Int] = [:]
        positions.reserveCapacity(songs.count)
        for (i, s) in songs.enumerated() { positions[s.id] = i }

        var added = 0
        var updated = 0
        let fm = FileManager.default

        for item in items where !purged.contains(item.id) {
            if let i = positions[item.id] {
                var changed = false
                if !songs[i].titleOverridden && songs[i].title != item.title {
                    songs[i].title = item.title
                    changed = true
                }
                if songs[i].file != item.file { songs[i].file = item.file; changed = true }
                if songs[i].mtime != item.mtime { songs[i].mtime = item.mtime; changed = true }
                if songs[i].size != item.size { songs[i].size = item.size; changed = true }
                if songs[i].hasOCR != item.hasOCR { songs[i].hasOCR = item.hasOCR; changed = true }
                if songs[i].thumbVersion != item.thumbVersion {
                    songs[i].thumbVersion = item.thumbVersion
                    songs[i].hasThumb = false
                    try? fm.removeItem(at: Paths.thumb(item.id))
                    changed = true
                }
                if changed { updated += 1 }
            } else {
                var song = Song(id: item.id, title: item.title, file: item.file)
                song.size = item.size
                song.mtime = item.mtime
                song.thumbVersion = item.thumbVersion
                song.hasOCR = item.hasOCR
                songs.append(song)
                positions[item.id] = songs.count - 1
                added += 1
            }
        }

        if added > 0 || updated > 0 {
            invalidate(index: true)
            saveSongsSoon()
        }
        return (added, updated)
    }

    // MARK: - 缓存

    func cacheBytes() -> Int64 { Paths.directorySize(Paths.originals) }

    private var downloadCount = 0

    /// 每次下载原图后调用；每 20 次才扫一次目录做淘汰，避免频繁 IO
    func noteOriginalDownloaded() {
        downloadCount += 1
        if downloadCount % 20 == 0 { evictCacheIfNeeded() }
    }

    func clearOriginalCache() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: Paths.originals.path) {
            for f in files { try? fm.removeItem(at: Paths.originals.appendingPathComponent(f)) }
        }
        invalidate(index: false)
    }

    func evictCacheIfNeeded() {
        let limit = Int64(max(128, settings.cacheLimitMB)) * 1024 * 1024
        let dir = Paths.originals
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var total: Int64 = 0
        var entries: [(URL, Int64, Date)] = []
        for url in files {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(v?.fileSize ?? 0)
            total += size
            entries.append((url, size, v?.contentModificationDate ?? Date.distantPast))
        }
        guard total > limit else { return }
        entries.sort { $0.2 < $1.2 }
        for entry in entries {
            if total <= limit { break }
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.1
        }
    }

    // MARK: - 备份 / 恢复

    func exportBackup() -> URL? {
        let bundle = BackupBundle(
            version: 1,
            exportedAt: Date().timeIntervalSince1970,
            songs: songs,
            tags: tags,
            history: history
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bundle) else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("歌谱备份-\(df.string(from: Date())).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func importBackup(from url: URL) -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return "无法读取该文件" }
        guard let bundle = try? JSONDecoder().decode(BackupBundle.self, from: data) else { return "文件格式不正确，不是本 App 的备份" }

        // 标签按名字合并
        var existingNames = Set(tags.map { $0.name })
        for tag in bundle.tags where !existingNames.contains(tag.name) {
            tags.append(tag)
            existingNames.insert(tag.name)
        }

        // 歌谱按 id 合并，本地较新的保留
        rebuildIndexIfNeeded()
        var map = songIndex
        for song in bundle.songs {
            if let current = map[song.id] {
                if song.updatedAt > current.updatedAt {
                    map[song.id] = song
                }
            } else {
                map[song.id] = song
            }
        }
        songs = Array(map.values)
        history = bundle.history
        invalidate(index: true)
        saveSongs()
        saveTags()
        saveHistory()
        return "恢复完成：\(bundle.songs.count) 首、\(bundle.tags.count) 个标签"
    }

    // MARK: - 持久化

    private func writeSongs(_ snapshot: [Song]) {
        JSONFile.write(snapshot, to: Paths.file("songs.json"))
    }

    func saveSongsSoon() {
        saveWork?.cancel()
        let snapshot = songs
        let work = DispatchWorkItem { JSONFile.write(snapshot, to: Paths.file("songs.json")) }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveSongs() {
        writeSongs(songs)
    }

    func saveTags() { JSONFile.write(tags, to: Paths.file("tags.json")) }
    func saveHistory() { JSONFile.write(history, to: Paths.file("history.json")) }

    func saveSettings() {
        JSONFile.write(settings, to: Paths.file("settings.json"))
        PinyinProvider.shared.saveIfNeeded()
    }

    func saveDirtySoon() {
        let snapshot = dirty
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            JSONFile.write(snapshot, to: Paths.file("dirty.json"))
        }
    }

    func saveDirtyNow() { JSONFile.write(dirty, to: Paths.file("dirty.json")) }
    func savePending() { JSONFile.write(pendingDeletes, to: Paths.file("pending.json")) }
    func savePurged() { JSONFile.write(purged, to: Paths.file("purged.json")) }
    func saveOCR() { JSONFile.write(ocr, to: Paths.file("ocr.json")) }
    func saveSyncMeta() { JSONFile.write(syncMeta, to: Paths.file("syncmeta.json")) }

    func flushAll() {
        saveWork?.cancel()
        saveSongs()
        saveTags()
        saveHistory()
        saveSettings()
        saveDirtyNow()
        savePending()
        savePurged()
        saveOCR()
        saveSyncMeta()
        PinyinProvider.shared.saveIfNeeded()
    }

    // MARK: - 外观

    var colorScheme: ColorScheme? {
        switch settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
