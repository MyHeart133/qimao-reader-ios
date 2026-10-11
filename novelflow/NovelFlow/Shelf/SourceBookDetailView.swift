import SwiftUI

/// 来源书籍详情:能力真实的操作入口(没有下载能力就不显示下载按钮)
///
/// 两类书源:
/// - 直链文件来源(Gutenberg 等):「下载并加入书架」
/// - 逐章书源(七猫/番茄/起点):「缓存全本并加入书架」(逐章抓取,可断点续传)
struct SourceBookDetailView: View {
    let book: SourceBook

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var cacheManager = ChapterCacheManager.shared

    @State private var onlinePreparing = false
    @State private var readerBook: ShelfBook?
    @State private var onlineNote: String?

    private var task: DownloadTask? {
        downloadManager.task(id: book.id)
    }

    private var source: ContentSource? {
        SourceRegistry.shared.source(withID: book.sourceID)
    }

    private var sourceDisplayName: String {
        source?.displayName ?? book.sourceID
    }

    private var supportsChapterCache: Bool {
        book.downloadURL == nil && (source?.capabilities.onlineReading ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let note = onlineNote {
                        noteBar(note)
                    }
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
        .fullScreenCover(item: $readerBook) { shelf in
            ReaderScreen(shelfBook: shelf)
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
                fileDownloadBlock
            } else if supportsChapterCache {
                chapterCacheBlock
            } else {
                Text("该来源未提供直接下载地址")
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
            }

            switchSourceBlock

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

    // MARK: 直链文件下载(Gutenberg 等)

    @ViewBuilder
    private var fileDownloadBlock: some View {
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
    }

    // MARK: 逐章缓存(七猫/番茄/起点)

    @ViewBuilder
    private var chapterCacheBlock: some View {
        let st = cacheManager.state(for: book)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                startOnlineReading()
            } label: {
                HStack {
                    Image(systemName: "book.fill")
                    Text(onlinePreparing ? "正在准备目录…" : "开始阅读(在线)")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(onlinePreparing ? Color.gray : NFTheme.accent)
                .cornerRadius(12)
            }
            .disabled(onlinePreparing)

            if let st {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(st.statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NFTheme.textPrimary)
                        Spacer()
                        if st.state == .downloading || st.state == .queued {
                            ProgressView(value: st.fraction)
                                .tint(NFTheme.accent)
                                .frame(width: 110)
                        }
                    }
                    if let msg = st.message, !msg.isEmpty, st.state != .downloading {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(st.state == .failed ? .red : NFTheme.textSecondary)
                    }

                    HStack(spacing: 10) {
                        switch st.state {
                        case .downloading, .queued:
                            smallButton("暂停", "pause.circle") { cacheManager.pause(book) }
                            smallButton("取消", "xmark.circle") { cacheManager.cancel(book) }
                        case .paused:
                            smallButton("继续缓存", "play.circle") { cacheManager.resume(book) }
                            smallButton("取消", "xmark.circle") { cacheManager.cancel(book) }
                        case .failed:
                            smallButton("重试", "arrow.clockwise.circle") { cacheManager.enqueue(book) }
                            smallButton("取消", "xmark.circle") { cacheManager.cancel(book) }
                        case .completed:
                            Label("已加入书架", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(NFTheme.accent)
                            smallButton("检查更新", "arrow.clockwise.circle") { cacheManager.enqueue(book) }
                        case .cancelled:
                            smallButton("重新缓存", "arrow.clockwise.circle") { cacheManager.enqueue(book) }
                        }
                    }
                }
                .padding(10)
                .background(Color.white)
                .cornerRadius(8)
            } else {
                Button {
                    cacheManager.enqueue(book)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("缓存全本并加入书架")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(NFTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(NFTheme.accentSoft)
                    .cornerRadius(10)
                }
                Text("在线读:点开即读,边读边缓存;缓存全本:整本落盘,离线可读。")
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary)
            }
        }
    }

    // MARK: 在线阅读

    private func startOnlineReading() {
        guard !onlinePreparing else { return }
        onlinePreparing = true
        onlineNote = nil
        Task {
            do {
                guard let source else { throw SourceError.unsupported("书源未注册") }
                let chapters = try await source.fetchChapterList(book.sourceBookID)
                guard !chapters.isEmpty else { throw SourceError.notFound }
                let meta = OnlineBookMeta(
                    sourceID: book.sourceID,
                    sourceBookID: book.sourceBookID,
                    title: book.title,
                    author: book.author,
                    chapters: chapters.map { OnlineChapterRef(id: $0.id, title: $0.title) },
                    updatedAt: Date()
                )
                let shelf = try LibraryService.ensureOnlineShelfBook(book: book, meta: meta, context: context)
                onlinePreparing = false
                readerBook = shelf
            } catch {
                onlinePreparing = false
                onlineNote = "打开失败:\(error.localizedDescription)"
            }
        }
    }

    private func noteBar(_ note: String) -> some View {
        HStack {
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(NFTheme.textPrimary)
            Spacer()
            Button {
                onlineNote = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(NFTheme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NFTheme.accentSoft)
        .cornerRadius(8)
    }

    private func smallButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NFTheme.accent)
        }
    }

    // MARK: 换源

    @ViewBuilder
    private var switchSourceBlock: some View {
        NavigationLink {
            SourceSwitchView(book: book)
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("换源 · 在其它书源中查找本书")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary)
            }
            .foregroundStyle(NFTheme.accent)
            .padding(12)
            .background(NFTheme.accentSoft)
            .cornerRadius(10)
        }
    }

    // MARK: 文案

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
