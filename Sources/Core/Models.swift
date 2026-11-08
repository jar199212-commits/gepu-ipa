import Foundation

// MARK: - 歌谱
/// 一首歌谱的全部本地数据。识别唯一依据是 id（内容哈希），文件名不参与识别。
struct Song: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// 相对 WebDAV 根目录的原图路径，例如 library/xxx.jpg
    var file: String
    var size: Int64
    var mtime: Double
    var favorite: Bool
    /// 绑定的标签 id 列表
    var tags: [String]
    var note: String
    /// 是否被用户手动改过名（改过名后同步不再覆盖标题）
    var titleOverridden: Bool
    var addedAt: Double
    var updatedAt: Double
    var thumbVersion: Int
    var hasThumb: Bool
    var hasOCR: Bool
    var inTrash: Bool
    var deletedAt: Double?

    init(id: String, title: String, file: String) {
        self.id = id
        self.title = title
        self.file = file
        self.size = 0
        self.mtime = 0
        self.favorite = false
        self.tags = []
        self.note = ""
        self.titleOverridden = false
        self.addedAt = Date().timeIntervalSince1970
        self.updatedAt = 0
        self.thumbVersion = 0
        self.hasThumb = false
        self.hasOCR = false
        self.inTrash = false
        self.deletedAt = nil
    }

    enum CodingKeys: String, CodingKey {
        case id, title, file, size, mtime, favorite, tags, note
        case titleOverridden, addedAt, updatedAt, thumbVersion, hasThumb, hasOCR, inTrash, deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "未命名"
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        mtime = try c.decodeIfPresent(Double.self, forKey: .mtime) ?? 0
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        titleOverridden = try c.decodeIfPresent(Bool.self, forKey: .titleOverridden) ?? false
        addedAt = try c.decodeIfPresent(Double.self, forKey: .addedAt) ?? 0
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        thumbVersion = try c.decodeIfPresent(Int.self, forKey: .thumbVersion) ?? 0
        hasThumb = try c.decodeIfPresent(Bool.self, forKey: .hasThumb) ?? false
        hasOCR = try c.decodeIfPresent(Bool.self, forKey: .hasOCR) ?? false
        inTrash = try c.decodeIfPresent(Bool.self, forKey: .inTrash) ?? false
        deletedAt = try c.decodeIfPresent(Double.self, forKey: .deletedAt)
    }
}

// MARK: - 标签
struct SongTag: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Double

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date().timeIntervalSince1970
    }
}

// MARK: - 浏览记录
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String          // 歌谱 id
    var openedAt: Double
}

// MARK: - 设置
struct Settings: Codable {
    var baseURL: String = ""
    var username: String = ""
    var password: String = ""
    /// 仅在 IPv6 网络下允许同步
    var onlyIPv6: Bool = true
    /// 原图缓存上限（MB）
    var cacheLimitMB: Int = 2048
    /// 浏览记录最多保存条数
    var maxHistory: Int = 500
    /// 回收站自动清理天数
    var trashDays: Int = 30
    /// system / light / dark
    var appearance: String = "system"
    /// 是否拉取 OCR 文本（关闭则只能按歌名搜索）
    var downloadOCR: Bool = true

    enum CodingKeys: String, CodingKey {
        case baseURL, username, password, onlyIPv6, cacheLimitMB
        case maxHistory, trashDays, appearance, downloadOCR
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        onlyIPv6 = try c.decodeIfPresent(Bool.self, forKey: .onlyIPv6) ?? true
        cacheLimitMB = try c.decodeIfPresent(Int.self, forKey: .cacheLimitMB) ?? 2048
        maxHistory = try c.decodeIfPresent(Int.self, forKey: .maxHistory) ?? 500
        trashDays = try c.decodeIfPresent(Int.self, forKey: .trashDays) ?? 30
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        downloadOCR = try c.decodeIfPresent(Bool.self, forKey: .downloadOCR) ?? true
    }
}

// MARK: - 同步进度
struct SyncProgress {
    var running = false
    var finished = false
    var phase = ""
    var total = 0
    var done = 0
    var added = 0
    var updated = 0
    var pushed = 0
    var removed = 0
    var errors: [String] = []
    var finishedAt: Double = 0

    var summary: String {
        if errors.isEmpty {
            return "新增 \(added) · 更新 \(updated) · 上推 \(pushed) · 删除 \(removed)"
        }
        return "新增 \(added) · 更新 \(updated) · 上推 \(pushed) · 删除 \(removed) · 失败 \(errors.count)"
    }
}

// MARK: - NAS 索引
struct RemoteIndex: Codable {
    var version: Int
    var generatedAt: Double
    var ocrVersion: String?
    var items: [RemoteItem]

    enum CodingKeys: String, CodingKey { case version, generatedAt, ocrVersion, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generatedAt = try c.decodeIfPresent(Double.self, forKey: .generatedAt) ?? 0
        ocrVersion = try c.decodeIfPresent(String.self, forKey: .ocrVersion)
        items = try c.decodeIfPresent([RemoteItem].self, forKey: .items) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encodeIfPresent(ocrVersion, forKey: .ocrVersion)
        try c.encode(items, forKey: .items)
    }
}

struct RemoteItem: Codable {
    var id: String
    var title: String
    var file: String
    var size: Int64
    var mtime: Double
    var thumbVersion: Int
    var hasOCR: Bool

    enum CodingKeys: String, CodingKey { case id, title, file, size, mtime, thumbVersion, hasOCR }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "未命名"
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        mtime = try c.decodeIfPresent(Double.self, forKey: .mtime) ?? 0
        thumbVersion = try c.decodeIfPresent(Int.self, forKey: .thumbVersion) ?? 0
        hasOCR = try c.decodeIfPresent(Bool.self, forKey: .hasOCR) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(file, forKey: .file)
        try c.encode(size, forKey: .size)
        try c.encode(mtime, forKey: .mtime)
        try c.encode(thumbVersion, forKey: .thumbVersion)
        try c.encode(hasOCR, forKey: .hasOCR)
    }
}

/// 数字库统计（首页空态展示）
struct LibraryStats {
    var total = 0
    var favorites = 0
    var trashed = 0
    var thumbs = 0
    var originals = 0
    var cacheBytes: Int64 = 0
}
