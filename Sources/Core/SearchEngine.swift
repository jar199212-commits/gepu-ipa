import Foundation

/// 拼音首字母缓存：40k 条歌名只算一次，落盘复用。
final class PinyinProvider {
    static let shared = PinyinProvider()

    private var cache: [String: String] = [:]
    private var loaded = false
    private var dirtyCount = 0
    private let lock = NSLock()

    private var fileURL: URL { Paths.file("pinyin.json") }

    func load() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
    }

    func saveIfNeeded() {
        lock.lock()
        let shouldSave = dirtyCount > 0
        let snapshot = cache
        dirtyCount = 0
        lock.unlock()
        guard shouldSave else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 取歌名的拼音首字母，如“奇异恩典” -> qyed
    func initials(for text: String) -> String {
        load()
        lock.lock()
        if let hit = cache[text] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let value = PinyinProvider.compute(text)

        lock.lock()
        cache[text] = value
        dirtyCount += 1
        lock.unlock()
        return value
    }

    static func compute(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        latin = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        latin = latin.lowercased()
        var out = ""
        for token in latin.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }) {
            if let first = token.first, first.isLetter || first.isNumber {
                out.append(first)
            }
        }
        return out
    }
}

/// 内存搜索索引。歌名（繁简归一）+ 拼音首字母 + OCR 文本三路匹配。
final class SearchEngine: @unchecked Sendable {
    struct Doc {
        var id: String
        var title: String
        var py: String
        var ocr: String
    }

    private var docs: [Doc] = []

    func setDocs(_ newDocs: [Doc]) {
        docs = newDocs
    }

    var count: Int { docs.count }

    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let hans = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        return hans.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func search(_ rawQuery: String, limit: Int = 3000) -> [String] {
        let q = SearchEngine.normalize(rawQuery)
        guard !q.isEmpty else { return [] }
        let isAscii = q.allSatisfy { $0.isASCII }
        var prefixHits: [String] = []
        var titleHits: [String] = []
        var pyHits: [String] = []
        var ocrHits: [String] = []

        for doc in docs {
            if doc.title.hasPrefix(q) {
                prefixHits.append(doc.id)
                continue
            }
            if doc.title.contains(q) {
                titleHits.append(doc.id)
                continue
            }
            if isAscii && !doc.py.isEmpty && doc.py.contains(q) {
                pyHits.append(doc.id)
                continue
            }
            if !doc.ocr.isEmpty && doc.ocr.contains(q) {
                ocrHits.append(doc.id)
            }
        }

        var result: [String] = []
        result.reserveCapacity(min(limit, prefixHits.count + titleHits.count + pyHits.count + ocrHits.count))
        for list in [prefixHits, titleHits, pyHits, ocrHits] {
            for id in list {
                if result.count >= limit { return result }
                result.append(id)
            }
        }
        return result
    }
}
