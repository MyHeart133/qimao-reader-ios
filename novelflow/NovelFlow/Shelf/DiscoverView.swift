import SwiftUI
import UniformTypeIdentifiers

/// 书库:开放来源搜索(Gutenberg 等)+ 本地导入 + 下载中心入口
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
                TextField("搜索多来源书库(书名 / 作者)", text: $query)
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
        if searching {
            Spacer()
            ProgressView("搜索中…")
            Spacer()
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
                Text("已检索:Gutenberg / Open Library / Webnovel(阅文官方)")
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary.opacity(0.8))
                Button("浏览中文公版馆藏(400+ 本)") { browseChinese() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NFTheme.accent)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
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
                    Label("开放书库", systemImage: "globe.asia.australia")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                    Text("接入三个来源:Project Gutenberg(7 万+ 公版书)、Open Library(全球书目)、Webnovel(阅文官方英译,如 Reverend Insanity)。")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineSpacing(3)
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
                    importNote = "导入失败：\(error.localizedDescription)"
                }
            }
        case .failure(let error):
            importNote = "导入失败：\(error.localizedDescription)"
        }
    }

    private func browseChinese() {
        guard !searching else { return }
        searching = true
        errorText = nil
        searched = true
        Task {
            do {
                let books = try await GutendexSource().browseChinese()
                results = books
            } catch {
                errorText = "加载失败：\(error.localizedDescription)"
                results = []
            }
            searching = false
        }
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !searching else { return }
        searching = true
        errorText = nil
        searched = true
        Task {
            let merged = await SourceRegistry.shared.searchAll(q)
            results = merged
            searching = false
        }
    }
}
