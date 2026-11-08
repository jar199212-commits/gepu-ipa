import Foundation
import Darwin

struct WebDAVConfig {
    var baseURL: String
    var username: String
    var password: String
    var onlyIPv6: Bool
}

enum DAVError: LocalizedError {
    case invalidURL(String)
    case notIPv6(String)
    case http(Int, String)
    case emptyBody(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let v):
            return "NAS 地址无效：\(v)"
        case .notIPv6(let host):
            return "域名 \(host) 没有 AAAA（IPv6）记录，已拒绝同步。请填写 IPv6 地址或具备 AAAA 解析的域名。"
        case .http(let code, let body):
            let hint: String
            switch code {
            case 401: hint = "账号或密码错误"
            case 403: hint = "账号无权限或目录未开启 WebDAV 写权限"
            case 404: hint = "文件或目录不存在"
            case 405: hint = "服务端不允许该操作"
            case 507: hint = "NAS 存储空间不足"
            default: hint = "服务端返回异常状态"
            }
            return "HTTP \(code)：\(hint)\(body.isEmpty ? "" : "（\(body.prefix(160))）")"
        case .emptyBody(let path):
            return "\(path) 返回空内容"
        case .cancelled:
            return "已取消"
        }
    }
}

/// 极简 WebDAV 客户端：GET / PUT / DELETE / PROPFIND / HEAD，基础认证。
final class WebDAVClient {
    let config: WebDAVConfig
    private let session: URLSession

    init(config: WebDAVConfig) {
        self.config = config
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 900
        c.httpMaximumConnectionsPerHost = 6
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        session = URLSession(configuration: c)
    }

    // MARK: - 地址

    private var normalizedBase: String {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return "" }
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") { base = "http://" + base }
        if !base.hasSuffix("/") { base += "/" }
        return base
    }

    private func encodedPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map { String($0) }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
    }

    func url(for path: String) throws -> URL {
        guard !normalizedBase.isEmpty else { throw DAVError.invalidURL(config.baseURL) }
        let full = normalizedBase + encodedPath(path)
        guard let url = URL(string: full) else { throw DAVError.invalidURL(full) }
        return url
    }

    // MARK: - IPv6 校验

    /// 只允许 IPv6：IPv6 字面量直接通过，域名必须能解析出 AAAA。
    func verifyIPv6IfNeeded() throws {
        guard config.onlyIPv6 else { return }
        guard let comps = URLComponents(string: normalizedBase), let host = comps.host, !host.isEmpty else {
            throw DAVError.invalidURL(config.baseURL)
        }
        if host.contains(":") { return }   // IPv6 字面量（URLComponents 会去掉方括号）
        if !WebDAVClient.hostResolvesIPv6(host) {
            throw DAVError.notIPv6(host)
        }
    }

    static func hostResolvesIPv6(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        if let result { freeaddrinfo(result) }
        return status == 0
    }

    // MARK: - 请求

    private func request(_ method: String, _ path: String, body: Data? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        var req = URLRequest(url: try url(for: path))
        req.httpMethod = method
        if !config.username.isEmpty || !config.password.isEmpty {
            let raw = "\(config.username):\(config.password)"
            req.setValue("Basic " + Data(raw.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        req.setValue("GePu/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = body }
        return req
    }

    private func check(_ response: URLResponse, _ data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { throw DAVError.http(0, "") }
        guard (200...299).contains(http.statusCode) else {
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw DAVError.http(http.statusCode, text)
        }
    }

    func get(_ path: String) async throws -> Data {
        let req = try request("GET", path)
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        return data
    }

    func getJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await get(path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DAVError.emptyBody(path)
        }
    }

    func download(_ path: String, to destination: URL) async throws {
        let req = try request("GET", path)
        let (tmp, response) = try await session.download(for: req)
        try check(response, nil)
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: tmp, to: destination)
    }

    func put(_ path: String, data: Data) async throws {
        let req = try request("PUT", path, body: data)
        let (body, response) = try await session.data(for: req)
        try check(response, body)
    }

    func delete(_ path: String) async throws {
        let req = try request("DELETE", path)
        let (body, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DAVError.http(0, "") }
        if http.statusCode == 404 { return }   // 已经不存在，视为成功
        try check(response, body)
    }

    /// PROPFIND Depth:0，用于连通性测试
    func propfind(_ path: String) async throws {
        var req = try request("PROPFIND", path, body: Data(), headers: ["Depth": "0"])
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let (body, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DAVError.http(0, "") }
        if http.statusCode == 401 { throw DAVError.http(401, "") }
        if (200...299).contains(http.statusCode) { return }
        if http.statusCode == 405 { return }   // 部分服务端禁用 PROPFIND，仍可继续
        throw DAVError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
    }

    /// 连通性测试，返回一句人话结论
    func testConnection() async throws -> String {
        try verifyIPv6IfNeeded()
        try await propfind("")
        do {
            let index: RemoteIndex = try await getJSON("index.json", as: RemoteIndex.self)
            return "连接成功 · 索引 \(index.items.count) 首 · 生成于 \(Self.dateText(index.generatedAt))"
        } catch {
            return "连接成功，但未读到 index.json（请先在 NAS 上运行索引脚本）"
        }
    }

    static func dateText(_ ts: Double) -> String {
        guard ts > 0 else { return "未知时间" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: Date(timeIntervalSince1970: ts))
    }
}
