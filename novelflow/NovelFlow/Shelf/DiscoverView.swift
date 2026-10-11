import SwiftUI
import UniformTypeIdentifiers

/// 书库:全网书源搜索(七猫/起点/番茄等)+ 本地导入 + 下载中心入口
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var downloadManager = DownloadManager.shared

    @State private var query = ""
    @State private var results: [SourceBook] = []
    @State private var searching = false
    @State private var searched = false
    @State private var errorText: String?
    @State private var showImporter = false
    @State private var importNote: String?
    @State private var sheetRoute: SheetRoute?
    @State private var showLinkPrompt = false
    @State private var linkInput = ""
    @State private var searchProgress = ""
    @State private var searchTask: Task<Void, Never>?

    private enum SheetRoute: Identifiable {
        case detail(SourceBook)
        case downloads

        var id: String {
            switch self {
            case .detail(let book): return "detail-\(book.id)"
            case .downloads: return "downloads"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let note = importNote {
                noteBar(note)
            }
            content
        }
        .background(NFTheme.background)
        .navigationTitle("书库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetRoute = .downloads
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 17))
                        if downloadManager.unfinishedCount > 0 {
                            Text("\(downloadManager.unfinishedCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(NFTheme.accent)
                                .clipShape(Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                    .foregroundStyle(NFTheme.accent)
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .detail(let book):
                SourceBookDetailView(book: book)
            case .downloads:
                DownloadsView()
            }
        }
        .alert("打开链接 / ID", isPresented: $showLinkPrompt) {
            TextField("粘贴番茄或起点的分享链接 / 书籍 ID", text: $linkInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("打开") { openLink() }
            Button("取消", role: .cancel) { linkInput = "" }
        } message: {
            Text("支持 fanqienovel.com 与 m.qidian.com 的书籍/章节链接,或直接输入书籍 ID。")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    // MARK: 搜索栏

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(NFTheme.textSecondary)
                TextField("搜索全网书源(书名 / 作者)", text: $query)
                    .font(.system(size: 15))
                    .submitLabel(.search)
                    .onSubmit { doSearch() }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(NFTheme.textSecondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white)
            .cornerRadius(19)

            Button {
                showLinkPrompt = true
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NFTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(NFTheme.accentSoft)
                    .clipShape(Circle())
            }

            Button {
                showImporter = true
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NFTheme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NFTheme.background)
    }

    // MARK: 状态条

    private func noteBar(_ note: String) -> some View {
        HStack {
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(NFTheme.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                importNote = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(NFTheme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(NFTheme.accentSoft)
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        if searching && results.isEmpty {
            VStack(spacing: 8) {
                ProgressView("搜索中…")
                Text(searchProgress.isEmpty
                     ? "多源并发检索,先到先显示"
                     : "已检索 \(searchProgress) 个来源,先到先显示")
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let e = errorText {
            VStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(NFTheme.textSecondary.opacity(0.5))
                Text(e).font(.system(size: 14)).foregroundStyle(NFTheme.textSecondary)
                Button("重试") { doSearch() }
                    .foregroundStyle(NFTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            Spacer()
        } else if !searched {
            emptyState
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Text("未找到相关书籍").font(.system(size: 14)).foregroundStyle(NFTheme.textSecondary)
                Text("已检索:\(searchableSourceNames)")
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button("浏览中文公版馆藏(400+ 本)") { browseChinese() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NFTheme.accent)
                    .padding(.top, 2)
                Button("看番茄热榜") { browseFanqieRank() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NFTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if searching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("还在搜索其它来源…(\(searchProgress))")
                                .font(.system(size: 12))
                                .foregroundStyle(NFTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.bottom, 2)
                    }
                    ForEach(results) { book in
                        Button {
                            sheetRoute = .detail(book)
                        } label: {
                            SourceBookCard(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
    }

    private var searchableSourceNames: String {
        SourceRegistry.shared.searchableSources.map(\.displayName).joined(separator: " / ")
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("导入本地书籍", systemImage: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                    Text("支持 TXT(UTF-8 / UTF-16 / GB18030)与 EPUB 2/3。文件只在你的设备上处理,不会上传。")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineSpacing(3)
                    Button {
                        showImporter = true
                    } label: {
                        Text("选择文件…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(NFTheme.accent)
                            .cornerRadius(10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 10) {
                    Label("全网书源", systemImage: "globe.asia.australia")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                    Text("中文网络小说:七猫 / 起点 / 番茄 + 多个聚合书源(202小说网 / 非凡中文 / 新笔趣阁 / 飘天文学 / 笔趣阁365),冷门书、老书、下架书都能搜到;另接入 Gutenberg / Open Library / Webnovel。")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineSpacing(3)
                    HStack(spacing: 10) {
                        Button {
                            browseFanqieRank()
                        } label: {
                            Text("看番茄热榜")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(NFTheme.accent)
                                .cornerRadius(9)
                        }
                        Button {
                            showLinkPrompt = true
                        } label: {
                            Text("链接打开…")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NFTheme.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(NFTheme.accentSoft)
                                .cornerRadius(9)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 10) {
                    Label("中文公版馆藏", systemImage: "text.book.closed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                    Text("Gutenberg 收录 400+ 本中文经典(唐诗三百首、红楼梦、水浒传……),全部可下载、可离线阅读。")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineSpacing(3)
                    Button {
                        browseChinese()
                    } label: {
                        Text("浏览中文馆藏")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(NFTheme.accent)
                            .cornerRadius(10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
            }
            .padding(14)
        }
    }

    // MARK: 动作

    private var importTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let epub = UTType(filenameExtension: "epub") {
            types.append(epub)
        }
        types.append(.text)
        return types
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let imported: ImportedBook = try await Task.detached(priority: .userInitiated) {
                        try LocalImporter.importFile(at: url)
                    }.value
                    try LibraryService.addImported(imported, sourceID: "local-import", context: context)
                    importNote = "已导入《\(imported.title)》到书架"
                } catch {
                    importNote = "导入失败:\(error.localizedDescription)"
                }
            }
        case .failure(let error):
            importNote = "导入失败:\(error.localizedDescription)"
        }
    }

    private func browseChinese() {
        guard !searching else { return }
        searching = true
        searchProgress = ""
        errorText = nil
        searched = true
        Task {
            do {
                let books = try await GutendexSource().browseChinese()
                results = books
            } catch {
                errorText = "加载失败:\(error.localizedDescription)"
                results = []
            }
            searching = false
        }
    }

    private func browseFanqieRank() {
        guard !searching else { return }
        searching = true
        searchProgress = ""
        errorText = nil
        searched = true
        Task {
            do {
                let books = try await FanqieSource().topRank(limit: 30)
                results = books
            } catch {
                errorText = "加载失败:\(error.localizedDescription)"
                results = []
            }
            searching = false
        }
    }

    /// 链接 / ID 直达(番茄、起点)
    private func openLink() {
        let input = linkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        linkInput = ""
        guard let resolved = WebLinkResolver.resolve(input) else {
            importNote = "无法识别链接或 ID(支持番茄 / 起点)"
            return
        }
        guard !searching else { return }
        searching = true
        searchProgress = ""
        errorText = nil
        searched = true
        Task {
            do {
                let book: SourceBook
                switch resolved {
                case .fanqieBook(let id):
                    book = try await FanqieSource().fetchDetail(id)
                case .fanqieChapter(let chapterID):
                    let src = FanqieSource()
                    let bookID = try await src.resolveBookID(fromChapter: chapterID)
                    book = try await src.fetchDetail(bookID)
                case .qidianBook(let id):
                    book = try await QidianSource().fetchDetail(id)
                }
                results = [book]
            } catch {
                errorText = "打开失败:\(error.localizedDescription)"
                results = []
            }
            searching = false
        }
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        searching = true
        errorText = nil
        searched = true
        results = []
        let total = SourceRegistry.shared.searchableSources.count
        searchProgress = "0/\(total)"
        searchTask = Task {
            var collected: [SourceBook] = []
            var done = 0
            for await batch in SourceRegistry.shared.searchStream(q) {
                if Task.isCancelled { return }
                done += 1
                collected.append(contentsOf: batch.books)
                results = SourceRegistry.dedupe(collected)
                searchProgress = "\(done)/\(total)"
            }
            searching = false
        }
    }
}
