import Foundation

/// 所有本地存储路径。Documents 会随 iTunes/访达备份，因此库数据与缩略图都放在这里。
enum Paths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var data: URL { ensure(documents.appendingPathComponent("data", isDirectory: true)) }
    static var thumbs: URL { ensure(documents.appendingPathComponent("thumbs", isDirectory: true)) }
    static var originals: URL { ensure(documents.appendingPathComponent("originals", isDirectory: true)) }
    static var logs: URL { ensure(documents.appendingPathComponent("logs", isDirectory: true)) }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    static func file(_ name: String) -> URL { data.appendingPathComponent(name) }
    static func thumb(_ id: String) -> URL { thumbs.appendingPathComponent("\(id).jpg") }
    static func original(_ id: String, file: String) -> URL {
        let ext = (file as NSString).pathExtension.lowercased()
        return originals.appendingPathComponent("\(id).\(ext.isEmpty ? "jpg" : ext)")
    }

    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func directorySize(_ dir: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }
}

enum JSONFile {
    static func read<T: Decodable>(_ url: URL, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum LogFile {
    static var url: URL { Paths.logs.appendingPathComponent("sync.log") }

    static func append(_ line: String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let text = "[\(df.string(from: Date()))] \(line)\n"
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        // 日志超过 2MB 时截断一半，避免无限增长
        if Paths.size(of: url) > 2_000_000 {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let half = String(content.suffix(content.count / 2))
                try? half.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "暂无同步日志"
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
