import SwiftUI

/// 来源书籍详情:能力真实的操作入口(没有下载能力就不显示下载按钮)
struct SourceBookDetailView: View {
    let book: SourceBook

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadManager = DownloadManager.shared

    private var task: DownloadTask? {
        downloadManager.task(id: book.id)
    }

    private var sourceDisplayName: String {
        SourceRegistry.shared.source(withID: book.sourceID)?.displayName ?? book.sourceID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let s = book.summary, !s.isEmpty {
                        section("简介") {
                            Text(s)
                                .font(.system(size: 14))
                                .foregroundStyle(NFTheme.textPrimary.opacity(0.9))
                                .lineSpacing(4)
                        }
                    }
                    if !book.subjects.isEmpty {
                        section("主题") {
                            Text(book.subjects.joined(separator: " · "))
                                .font(.system(size: 13))
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                    actionSection
                }
                .padding(16)
            }
            .background(NFTheme.background)
            .navigationTitle("书籍详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(NFTheme.accent)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: book.cover ?? "")) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    ZStack {
                        NFTheme.accentSoft
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(NFTheme.accent.opacity(0.5))
                    }
                }
            }
            .frame(width: 96, height: 134)
            .clipped()
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 7) {
                Text(book.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NFTheme.textPrimary)
                    .lineLimit(3)
                Text(book.author.isEmpty ? "未知作者" : book.author)
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
                if let lang = book.language {
                    Text("语言:\(lang.uppercased())")
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.textSecondary)
                }
                Text("来源:" + sourceDisplayName)
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary)
                if let dl = book.downloadCount, dl > 0 {
                    Text("累计下载 \(dl) 次")
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if book.downloadURL != nil {
                Button {
                    downloadManager.enqueue(book)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(buttonTitle)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(buttonColor)
                    .cornerRadius(12)
                }
                .disabled(task?.state.isActive == true || task?.state == .completed)
            } else {
                Text("该来源未提供直接下载地址")
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
            }

            if let t = task {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(t.state.displayName + (t.state == .completed ? " ✅ 已加入书架" : ""))
                            .font(.system(size: 13))
                            .foregroundStyle(NFTheme.textPrimary)
                        Spacer()
                        if !t.progressText.isEmpty {
                            Text(t.progressText)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                    if t.state == .downloading || t.state == .paused {
                        ProgressView(value: t.progress)
                            .tint(NFTheme.accent)
                    }
                    if let e = t.error, !e.isEmpty {
                        Text(e).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(Color.white)
                .cornerRadius(8)
            }

            if let ext = book.externalURL, let url = URL(string: ext) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "safari")
                        Text("在网页中查看")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(NFTheme.accent)
                }
            }
        }
    }

    private var buttonTitle: String {
        guard let t = task else {
            return "下载并加入书架(\(book.downloadFormat?.uppercased() ?? "TXT"))"
        }
        switch t.state {
        case .downloading: return "下载中…(可在下载中心查看)"
        case .queued: return "已排队…"
        case .paused: return "继续下载"
        case .completed: return "已加入书架"
        case .failed, .cancelled: return "重试下载"
        }
    }

    private var buttonColor: Color {
        guard let t = task else { return NFTheme.accent }
        switch t.state {
        case .completed: return Color.gray
        case .failed, .cancelled: return NFTheme.accent
        default: return Color.gray
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NFTheme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
    }
}
