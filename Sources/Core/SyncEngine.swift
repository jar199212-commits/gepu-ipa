import Foundation

/// 与 NAS 的双向同步。核心约定：
/// - 一切以歌谱 id（内容哈希）为索引，文件名只当作“地址”，改名不影响识别；
/// - 拉：索引 → 缩略图 → OCR 汇总；
/// - 推：本地改过的歌名 / 标签 / 收藏 / 笔记写成 meta/<id>.json；
/// - 删：永久删除的歌谱，同步时联动删除 NAS 上的原图、缩略图、OCR、元数据。
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private var isRunning = false

    private struct RemoteMeta: Codable {
        var id: String
        var title: String
        var titleOverridden: Bool
        var favorite: Bool
        var tags: [String]
        var note: String
        var updatedAt: Double
        var client: String
    }

    func testConnection(store: AppStore) async -> String {
        guard let client = store.webdav() else { return "请先填写 NAS 地址" }
        do {
            let text = try await client.testConnection()
            return text
        } catch {
            return error.localizedDescription
        }
    }

    func run(store: AppStore) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var progress = SyncProgress()
        progress.running = true
        progress.phase = "检查连接"
        store.syncProgress = progress
        LogFile.append("开始同步")

        func fail(_ message: String) {
            var p = store.syncProgress
            p.running = false
            p.finished = true
            p.phase = "失败"
            if p.errors.count < 60 { p.errors.append(message) }
            p.finishedAt = Date().timeIntervalSince1970
            store.syncProgress = p
            LogFile.append("同步失败：\(message)")
        }

        guard let client = store.webdav() else {
            fail("请先在「我的 → 设置 → NAS 同步」里填写 IPv6 WebDAV 地址")
            return
        }

        do {
            try client.verifyIPv6IfNeeded()
        } catch {
            fail(error.localizedDescription)
            return
        }

        // 1. 拉索引
        store.syncProgress.phase = "读取索引"
        let index: RemoteIndex
        do {
            index = try await client.getJSON("index.json", as: RemoteIndex.self)
        } catch {
            fail("读取 index.json 失败：\(error.localizedDescription)。请确认 NAS 上已运行 build_index.py，且地址填写到 index.json 所在目录。")
            return
        }
        LogFile.append("索引：\(index.items.count) 首，生成于 \(WebDAVClient.dateText(index.generatedAt))")

        // 2. 合并索引（新增 / 更新）
        store.syncProgress.phase = "更新歌谱索引"
        let merged = store.applyRemoteUpdate(index.items)
        store.syncProgress.added = merged.added
        store.syncProgress.updated = merged.updated

        // 3. 补缩略图
        let thumbsNeeded: [(String, Int)] = store.songs
            .filter { !$0.inTrash }
            .filter { !FileManager.default.fileExists(atPath: Paths.thumb($0.id).path) }
            .map { ($0.id, $0.thumbVersion) }

        if !thumbsNeeded.isEmpty {
            store.syncProgress.phase = "下载缩略图"
            store.syncProgress.total = thumbsNeeded.count
            store.syncProgress.done = 0

            var positions: [String: Int] = [:]
            positions.reserveCapacity(store.songs.count)
            for (i, song) in store.songs.enumerated() { positions[song.id] = i }

            let chunkSize = 6
            var start = 0
            var doneCount = 0
            var finishedIDs: [String] = []
            finishedIDs.reserveCapacity(thumbsNeeded.count)

            while start < thumbsNeeded.count {
                let end = min(start + chunkSize, thumbsNeeded.count)
                let chunk = Array(thumbsNeeded[start..<end])
                await withTaskGroup(of: (String, String?).self) { group in
                    for item in chunk {
                        let id = item.0
                        group.addTask {
                            do {
                                try await client.download("thumbs/\(id).jpg", to: Paths.thumb(id))
                                return (id, nil)
                            } catch {
                                return (id, error.localizedDescription)
                            }
                        }
                    }
                    for await result in group {
                        doneCount += 1
                        if let message = result.1 {
                            store.syncProgress.errors.append("缩略图 \(result.0)：\(message)")
                        } else {
                            finishedIDs.append(result.0)
                        }
                    }
                }
                store.syncProgress.done = doneCount
                start = end
            }

            if !finishedIDs.isEmpty {
                var updated = store.songs
                for id in finishedIDs {
                    if let pos = positions[id], pos < updated.count, updated[pos].id == id {
                        updated[pos].hasThumb = true
                    }
                }
                store.songs = updated
                store.saveSongsSoon()
            }
        }

        // 4. 拉 OCR 汇总（仅在版本变化时）
        if store.settings.downloadOCR {
            let remoteVersion = index.ocrVersion ?? ""
            if !remoteVersion.isEmpty && remoteVersion != store.syncMeta.ocrVersion {
                store.syncProgress.phase = "下载 OCR 文本"
                store.syncProgress.total = 1
                store.syncProgress.done = 0
                do {
                    let dict = try await client.getJSON("ocr.json", as: [String: String].self)
                    store.ocr = dict
                    store.saveOCR()
                    store.syncMeta.ocrVersion = remoteVersion
                    store.indexRevision += 1
                    store.syncProgress.done = 1
                    LogFile.append("OCR 文本：\(dict.count) 首")
                } catch {
                    store.syncProgress.errors.append("OCR 下载失败：\(error.localizedDescription)")
                }
            }
        }

        // 5. 上推本地修改
        let dirtyIDs = Array(store.dirty)
        if !dirtyIDs.isEmpty {
            store.syncProgress.phase = "上推本地修改"
            store.syncProgress.total = dirtyIDs.count
            store.syncProgress.done = 0
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for id in dirtyIDs {
                guard let song = store.song(id) else {
                    store.dirty.remove(id)
                    continue
                }
                let meta = RemoteMeta(
                    id: song.id,
                    title: song.title,
                    titleOverridden: song.titleOverridden,
                    favorite: song.favorite,
                    tags: song.tags,
                    note: song.note,
                    updatedAt: song.updatedAt,
                    client: "iPad"
                )
                do {
                    let data = try encoder.encode(meta)
                    try await client.put("meta/\(id).json", data: data)
                    store.dirty.remove(id)
                    store.syncProgress.pushed += 1
                } catch {
                    store.syncProgress.errors.append("上推 \(song.title)：\(error.localizedDescription)")
                }
                store.syncProgress.done += 1
            }
            store.saveDirtyNow()
        }

        // 6. 联动删除 NAS
        let pending = store.pendingDeletes
        if !pending.isEmpty {
            store.syncProgress.phase = "联动删除 NAS 文件"
            store.syncProgress.total = pending.count
            store.syncProgress.done = 0
            for (id, file) in pending {
                do {
                    if !file.isEmpty { try await client.delete(file) }
                    try await client.delete("thumbs/\(id).jpg")
                    try await client.delete("ocr/\(id).txt")
                    try await client.delete("meta/\(id).json")
                    store.pendingDeletes.removeValue(forKey: id)
                    store.syncProgress.removed += 1
                    LogFile.append("已删除 NAS：\(id) \(file)")
                } catch {
                    store.syncProgress.errors.append("删除 \(id)：\(error.localizedDescription)")
                }
                store.syncProgress.done += 1
            }
            store.savePending()
        }

        // 7. 收尾
        store.syncMeta.indexGeneratedAt = index.generatedAt
        store.syncMeta.lastSyncAt = Date().timeIntervalSince1970
        store.saveSyncMeta()

        var p = store.syncProgress
        p.running = false
        p.finished = true
        p.phase = p.errors.isEmpty ? "同步完成" : "同步完成（有失败项）"
        p.finishedAt = Date().timeIntervalSince1970
        store.syncProgress = p
        store.evictCacheIfNeeded()
        LogFile.append("同步结束：\(p.summary)")

        let remoteIDs = Set(index.items.map { $0.id })
        let ghosts = store.songs.filter { !$0.inTrash && !remoteIDs.contains($0.id) && !store.purged.contains($0.id) }
        if !ghosts.isEmpty {
            LogFile.append("注意：本地有 \(ghosts.count) 首在 NAS 索引中已不存在（可能被 NAS 侧删除），仍保留本地缓存。")
        }
    }
}
