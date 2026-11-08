import SwiftUI

// MARK: - 同步面板
struct SyncSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

    private var progress: SyncProgress { store.syncProgress }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if progress.running && progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .progressViewStyle(.linear)
                    Text("\(progress.done) / \(progress.total)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                counts

                if !progress.errors.isEmpty {
                    errorsView
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("NAS 同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            guard !started else { return }
            started = true
            Task { await SyncEngine.shared.run(store: store) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if progress.running {
                    ProgressView()
                } else {
                    Image(systemName: progress.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(progress.errors.isEmpty ? .green : .orange)
                }
                Text(progress.running ? progress.phase : (progress.finished ? progress.phase : "准备中"))
                    .font(.system(size: 16, weight: .semibold))
            }
            if store.settings.baseURL.isEmpty {
                Text("还没有填写 NAS 地址，请先到「我的 → 设置」里填写 IPv6 WebDAV 地址。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else if progress.finished {
                Text("上次同步：\(Fmt.time(progress.finishedAt))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var counts: some View {
        HStack(spacing: 0) {
            countItem("新增", progress.added, .green)
            countItem("更新", progress.updated, .blue)
            countItem("上推", progress.pushed, .purple)
            countItem("删除", progress.removed, .red)
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func countItem(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 20, weight: .semibold)).foregroundColor(color)
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var errorsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("失败项（\(progress.errors.count)）")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(progress.errors.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
