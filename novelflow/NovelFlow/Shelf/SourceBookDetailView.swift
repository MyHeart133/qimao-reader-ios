import SwiftUI

/// 来源书籍详情:能力真实的操作入口(没有下载能力就不显示下载按钮)
struct SourceBookDetailView: View {
    let book: SourceBook

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloader = BookDownloader.shared

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
                Text("来源:Gutenberg 开放书库(公共领域)")
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
                    downloader.download(book, context: context)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("下载并加入书架(\(book.downloadFormat?.uppercased() ?? "TXT"))")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(downloader.isBusy ? Color.gray : NFTheme.accent)
                    .cornerRadius(12)
                }
                .disabled(downloader.isBusy)
            } else {
                Text("该来源未提供直接下载地址")
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
            }

            if let job = downloader.job, job.id == book.id {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.phase + (job.phase == "完成" ? " ✅ 已加入书架" : ""))
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textPrimary)
                    if !job.isFinished {
                        ProgressView(value: job.progress)
                            .tint(NFTheme.accent)
                    }
                    if let e = job.error {
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
