import SwiftUI

/// 下载中心:任务列表 / 筛选 / 批量操作
struct DownloadsView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var filter: DownloadFilter = .all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("筛选", selection: $filter) {
                    ForEach(DownloadFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if !manager.tasks.isEmpty {
                    batchBar
                }

                let list = manager.filtered(filter)
                if list.isEmpty {
                    ContentUnavailableView {
                        Label("暂无任务", systemImage: "arrow.down.circle")
                    } description: {
                        Text("在书库中下载书籍后,任务会出现在这里。")
                    }
                } else {
                    List {
                        ForEach(list) { task in
                            DownloadRow(task: task, manager: manager)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(NFTheme.background)
            .navigationTitle("下载中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(NFTheme.accent)
                }
            }
        }
    }

    private var batchBar: some View {
        HStack(spacing: 12) {
            Button("全部暂停") { manager.pauseAll() }
                .disabled(!manager.tasks.contains { $0.state.isActive })
            Button("全部恢复") { manager.resumeAll() }
                .disabled(!manager.tasks.contains { $0.state == .paused })
            Spacer()
            Button("清除已结束") { manager.clearFinished() }
                .disabled(!manager.tasks.contains { $0.state.isFinished })
        }
        .font(.system(size: 13))
        .foregroundStyle(NFTheme.accent)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// 单任务行
struct DownloadRow: View {
    let task: DownloadTask
    @ObservedObject var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(task.state.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(stateColor)
                        if !task.progressText.isEmpty {
                            Text(task.progressText)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                        if !task.speedText.isEmpty {
                            Text(task.speedText)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                    if let e = task.error, !e.isEmpty {
                        Text(e)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer()
                actionButtons
            }

            if task.state == .downloading || task.state == .paused {
                if task.totalBytes > 0 {
                    ProgressView(value: task.progress)
                        .tint(task.state == .paused ? .gray : NFTheme.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(NFTheme.accent)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.state.isFinished || task.state == .paused {
                Button("删除", role: .destructive) { manager.remove(task.id) }
            }
            if task.state.isActive || task.state == .paused {
                Button("取消") { manager.cancel(task.id) }
                    .tint(.orange)
            }
        }
    }

    private var stateColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        case .paused: return .gray
        case .cancelled: return .gray
        default: return NFTheme.accent
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch task.state {
        case .downloading, .queued:
            smallButton("暂停", "pause.fill") { manager.pause(task.id) }
        case .paused:
            smallButton("恢复", "play.fill") { manager.resume(task.id) }
        case .failed, .cancelled:
            smallButton("重试", "arrow.clockwise") { manager.retry(task.id) }
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)
        }
    }

    private func smallButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 17))
                .frame(width: 40, height: 34)
                .foregroundStyle(NFTheme.accent)
        }
    }
}
