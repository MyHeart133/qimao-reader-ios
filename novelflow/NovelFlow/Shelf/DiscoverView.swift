import SwiftUI
import UniformTypeIdentifiers

/// 书库:开放来源搜索(Gutenberg 等)+ 本地导入入口
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var downloader = BookDownloader.shared

    @State private var query = ""
    @State private var results: [SourceBook] = []
    @State private var searching = false
    @State private var searched = false
    @State private var errorText: String?
    @State private var showImporter = false
    @State private var importNote: String?
    @State private var detailBook: SourceBook?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let note = importNote {
                noteBar(note)
            }
            if let job = downloader.job {
                downloadBar(job)
            }
            content
        }
        .background(NFTheme.background)
        .navigationTitle("书库")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailBook) { book in
            SourceBookDetailView(book: book)
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
                TextField("搜索 Gutenberg 开放书库(书名 / 作者)", text: $query)
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

    private func downloadBar(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("《\(job.title)》 \(job.phase)")
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if job.isFinished {
                    Button("清除") { downloader.clearFinished() }
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.accent)
                }
            }
            if !job.isFinished {
                ProgressView(value: job.progress)
                    .tint(NFTheme.accent)
            }
            if let e = job.error {
                Text(e).font(.system(size: 12)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
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
            VStack(spacing: 8) {
                Text("未找到相关书籍").font(.system(size: 14)).foregroundStyle(NFTheme.textSecondary)
                Text("试试英文书名或作者(Gutenberg 以公版书为主)")
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { book in
                        Button {
                            detailBook = book
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
                    Text("接入 Project Gutenberg(7 万+ 本公共领域书籍,允许自由下载与离线阅读)。试试搜索:Pride and Prejudice、Alice、Kafka、唐诗。")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineSpacing(3)
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

/// 书库结果卡片
struct SourceBookCard: View {
    let book: SourceBook

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: book.cover ?? "")) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    ZStack {
                        NFTheme.accentSoft
                        Image(systemName: "book.closed.fill").foregroundStyle(NFTheme.accent.opacity(0.5))
                    }
                }
            }
            .frame(width: 60, height: 84)
            .clipped()
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NFTheme.textPrimary)
                    .lineLimit(2)
                Text(book.author.isEmpty ? "未知作者" : book.author)
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
                    .lineLimit(1)
                if let s = book.summary, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let lang = book.language {
                        chip(lang.uppercased())
                    }
                    if let fmt = book.downloadFormat {
                        chip(fmt.uppercased() + " 可下载")
                    }
                    if let dl = book.downloadCount, dl > 0 {
                        chip("↓\(dl)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(NFTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(NFTheme.accentSoft)
            .cornerRadius(4)
    }
}
