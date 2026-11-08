import SwiftUI
import UIKit

/// 打开详情的入参：当前歌谱 + 本次的滑动范围
struct DetailTarget: Identifiable {
    let id: String
    let scope: [String]
}

enum Fmt {
    static func time(_ ts: Double) -> String {
        guard ts > 0 else { return "" }
        let date = Date(timeIntervalSince1970: ts)
        let df = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            df.dateFormat = "今天 HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            df.dateFormat = "昨天 HH:mm"
        } else {
            df.dateFormat = "yyyy-MM-dd HH:mm"
        }
        return df.string(from: date)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }
}

enum ImageCache {
    private static let thumbCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    static func thumb(_ id: String) -> UIImage? {
        if let hit = thumbCache.object(forKey: id as NSString) { return hit }
        let url = Paths.thumb(id)
        guard FileManager.default.fileExists(atPath: url.path),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        thumbCache.setObject(image, forKey: id as NSString)
        return image
    }

    static func forget(_ id: String) {
        thumbCache.removeObject(forKey: id as NSString)
    }
}

enum ImageLoader {
    /// 原图按需下载缓存；已缓存直接读盘
    @MainActor
    static func original(id: String, store: AppStore) async -> UIImage? {
        guard let song = store.song(id) else { return nil }
        let dest = Paths.original(id, file: song.file)
        if let image = UIImage(contentsOfFile: dest.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            return image
        }
        guard let client = store.webdav() else { return nil }
        do {
            try await client.download(song.file, to: dest)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            let image = UIImage(contentsOfFile: dest.path)
            store.noteOriginalDownloaded()
            return image
        } catch {
            return nil
        }
    }
}

// MARK: - 缩略图
struct SongThumb: View {
    let songID: String
    var corner: CGFloat = 8
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(Color(UIColor.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: songID) {
            if let cached = ImageCache.thumb(songID) {
                image = cached
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
            if Task.isCancelled { return }
            if let loaded = ImageCache.thumb(songID) {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

// MARK: - 列表行
struct SongRow: View {
    let song: Song
    @EnvironmentObject private var store: AppStore
    var showFavoriteButton = true

    var body: some View {
        HStack(spacing: 12) {
            SongThumb(songID: song.id)
                .frame(width: 48, height: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text(song.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !song.tags.isEmpty {
                        Text(store.tagNames(song.tags))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if !song.note.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            if showFavoriteButton {
                Button {
                    store.toggleFavorite(song.id)
                } label: {
                    Image(systemName: song.favorite ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(song.favorite ? .yellow : Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - 网格单元
struct SongGridCell: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                SongThumb(songID: song.id, corner: 10)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                if song.favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .padding(6)
                }
            }
            Text(song.title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TagChip: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 统一的空态
struct EmptyHint: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.7))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AppStore {
    func tagNames(_ ids: [String]) -> String {
        var names: [String] = []
        for id in ids.prefix(2) {
            if let tag = tags.first(where: { $0.id == id }) { names.append(tag.name) }
        }
        if ids.count > 2 { names.append("+\(ids.count - 2)") }
        return names.joined(separator: " · ")
    }
}
