import SwiftData
import SwiftUI
import UIKit

// MARK: - 阅读模型

@MainActor
final class ReaderModel: ObservableObject {
    @Published var chapters: [StoredChapterMeta] = []
    @Published var chapterIndex = 0
    @Published var pages: [PageSlice] = []
    @Published var pageIndex = 0
    @Published var loading = true
    @Published var errorText: String?
    @Published var typography = ReaderTypography()
    @Published var themeIndex = 0
    @Published private(set) var chapterText = ""
    @Published private(set) var pagingMillis: Double = 0
    @Published var readingMode: ReadingMode = .paged
    @Published var tapZonePreset: TapZonePreset = .standard
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var contentToken = 0
    /// 在线模式:当前章节正在抓取
    @Published private(set) var chapterLoading = false
    /// 在线模式:章节抓取失败信息
    @Published private(set) var chapterLoadError: String?

    private var fullText = ""
    private var bookID = ""
    private var context: ModelContext?
    private(set) var anchorOffset = 0
    private var lastSize: CGSize = .zero
    private var generation = 0
    private var configured = false
    /// 在线模式:目录与来源
    private var onlineMeta: OnlineBookMeta?
    private var onlineSource: ContentSource?
    private var onlineFetchGeneration = 0
    private var restoreAnchorOnLoad = false
    private var pendingPaginate: Task<Void, Never>?

    var isOnlineBook: Bool { onlineMeta != nil }

    var chapterTitle: String {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return "" }
        return chapters[chapterIndex].title
    }

    var pageCount: Int { pages.count }

    var currentPage: PageSlice? {
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        return pages[pageIndex]
    }

    var statusLine: String {
        let ch = chapters.isEmpty ? 0 : chapterIndex + 1
        if readingMode == .scroll {
            let length = max(1, (chapterText as NSString).length)
            let percent = min(100, max(0, Int(Double(anchorOffset) / Double(length) * 100)))
            return "第\(ch)/\(chapters.count)章 · \(percent)%"
        }
        let page = pages.isEmpty ? 0 : pageIndex + 1
        return "第\(ch)/\(chapters.count)章 · \(page)/\(max(pages.count, 1))页"
    }

    // MARK: 加载

    func configure(bookID: String, context: ModelContext, size: CGSize) {
        if size.width > 1, size.height > 1 {
            lastSize = size
        }
        guard !configured else { return }
        configured = true
        self.bookID = bookID
        self.context = context
        loading = true

        // 在线书籍:本地全文不存在但存在在线目录 → 在线模式(边读边缓存)
        if !BookContentStore.shared.exists(bookID: bookID),
           let meta = OnlineChapterStore.shared.meta(bookID: bookID) {
            self.onlineMeta = meta
            self.onlineSource = SourceRegistry.shared.source(withID: meta.sourceID)
            self.chapters = meta.chapters.enumerated().map { i, ch in
                StoredChapterMeta(index: i, title: ch.title, location: 0, length: 0)
            }
            self.restorePreferences()
            self.loadBookmarks()
            self.restoreProgress()
            if self.chapters.isEmpty {
                self.errorText = "本书没有可读章节"
            } else {
                self.enterChapter(index: min(self.chapterIndex, self.chapters.count - 1), keepAnchor: true)
            }
            self.loading = false
            return
        }

        Task {
            let outcome: Result<(String, [StoredChapterMeta]), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let text = try BookContentStore.shared.loadText(bookID: bookID)
                    let metas = try BookContentStore.shared.loadChapters(bookID: bookID)
                    return .success((text, metas))
                } catch {
                    return .failure(error)
                }
            }.value

            switch outcome {
            case .success(let (text, metas)):
                self.fullText = text
                self.chapters = metas
                self.restorePreferences()
                self.loadBookmarks()
                self.restoreProgress()
                if metas.isEmpty {
                    self.errorText = "本书没有可读章节"
                } else {
                    self.enterChapter(index: min(self.chapterIndex, metas.count - 1), keepAnchor: true)
                }
            case .failure(let e):
                self.errorText = e.localizedDescription
            }
            self.loading = false
        }
    }

    private func restoreProgress() {
        guard let context else { return }
        let bid = bookID
        let descriptor = FetchDescriptor<ReadingPosition>(
            predicate: #Predicate { $0.bookID == bid }
        )
        if let pos = (try? context.fetch(descriptor))?.first {
            chapterIndex = max(0, pos.chapterIndex)
            anchorOffset = max(0, pos.anchorOffset)
        }
    }

    private func restorePreferences() {
        if let raw = UserDefaults.standard.string(forKey: ReaderPreferenceKeys.readingMode),
           let mode = ReadingMode(rawValue: raw) {
            readingMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: ReaderPreferenceKeys.tapZone),
           let preset = TapZonePreset(rawValue: raw) {
            tapZonePreset = preset
        }
    }

    // MARK: 章节切换

    func enterChapter(index: Int, keepAnchor: Bool) {
        guard !chapters.isEmpty else { return }
        chapterIndex = max(0, min(index, chapters.count - 1))
        restoreAnchorOnLoad = keepAnchor
        loadChapterText()
        if !keepAnchor {
            anchorOffset = 0
        }
        pageIndex = 0
        contentToken += 1
        if !chapterLoading {
            paginate(keepAnchor: keepAnchor)
        } else {
            pages = []
        }
        saveProgress()
    }

    private func loadChapterText() {
        guard !chapters.isEmpty else { return }
        // 在线模式:命中缓存即读,否则异步抓取
        if let onlineMeta {
            let index = chapterIndex
            if let cached = OnlineChapterStore.shared.chapterText(bookID: bookID, index: index) {
                chapterText = cached
                chapterLoading = false
                chapterLoadError = nil
            } else {
                chapterText = ""
                chapterLoading = true
                chapterLoadError = nil
                fetchOnlineChapter(index: index, meta: onlineMeta)
            }
            return
        }
        let meta = chapters[chapterIndex]
        let ns = fullText as NSString
        let loc = min(max(0, meta.location), ns.length)
        let len = min(max(0, meta.length), ns.length - loc)
        chapterText = ns.substring(with: NSRange(location: loc, length: len))
    }

    // MARK: 在线章节抓取

    private func fetchOnlineChapter(index: Int, meta: OnlineBookMeta) {
        guard let source = onlineSource, index >= 0, index < meta.chapters.count else {
            chapterLoading = false
            chapterLoadError = "书源未注册,无法获取章节"
            return
        }
        let ref = meta.chapters[index]
        let bookID = self.bookID
        onlineFetchGeneration += 1
        let gen = onlineFetchGeneration
        Task { [weak self] in
            do {
                let text = try await source.fetchChapterContent(meta.sourceBookID, chapterID: ref.id)
                guard let self, gen == self.onlineFetchGeneration else { return }
                OnlineChapterStore.shared.saveChapter(bookID: bookID, index: index, text: text)
                guard self.chapterIndex == index else { return }
                self.chapterText = text
                self.chapterLoading = false
                self.contentToken += 1
                self.paginate(keepAnchor: self.restoreAnchorOnLoad)
                self.restoreAnchorOnLoad = false
                self.prefetchNeighbors(around: index, meta: meta, source: source)
            } catch {
                guard let self, gen == self.onlineFetchGeneration, self.chapterIndex == index else { return }
                self.chapterLoading = false
                self.chapterLoadError = error.localizedDescription
            }
        }
    }

    /// 预取相邻章节(后台,静默失败)
    private func prefetchNeighbors(around index: Int, meta: OnlineBookMeta, source: ContentSource) {
        let bookID = self.bookID
        for neighbor in [index + 1, index - 1] {
            guard neighbor >= 0, neighbor < meta.chapters.count else { continue }
            guard OnlineChapterStore.shared.chapterText(bookID: bookID, index: neighbor) == nil else { continue }
            let ref = meta.chapters[neighbor]
            Task.detached(priority: .utility) {
                if let text = try? await source.fetchChapterContent(meta.sourceBookID, chapterID: ref.id) {
                    OnlineChapterStore.shared.saveChapter(bookID: bookID, index: neighbor, text: text)
                }
            }
        }
    }

    /// 在线模式:重试当前章节
    func retryCurrentChapter() {
        guard let onlineMeta else { return }
        chapterLoadError = nil
        chapterLoading = true
        fetchOnlineChapter(index: chapterIndex, meta: onlineMeta)
    }

    /// 排版参数变更后的防抖重排(滑块连续拖动不产生分页风暴)
    func schedulePaginate() {
        pendingPaginate?.cancel()
        pendingPaginate = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.paginate(keepAnchor: true)
        }
    }

    func nextChapter() {
        guard chapterIndex + 1 < chapters.count else { return }
        enterChapter(index: chapterIndex + 1, keepAnchor: false)
    }

    func prevChapter() {
        guard chapterIndex > 0 else { return }
        enterChapter(index: chapterIndex - 1, keepAnchor: false)
    }

    func jump(toChapter index: Int) {
        enterChapter(index: index, keepAnchor: false)
    }

    /// 跳转到章内锚点(书签 / 搜索结果)
    func jump(toChapter index: Int, anchor: Int) {
        guard !chapters.isEmpty else { return }
        chapterIndex = max(0, min(index, chapters.count - 1))
        restoreAnchorOnLoad = true
        loadChapterText()
        anchorOffset = max(0, anchor)
        pages = []
        pageIndex = 0
        contentToken += 1
        if !chapterLoading {
            paginate(keepAnchor: true)
        }
        saveProgress()
    }

    func jump(to bookmark: Bookmark) {
        jump(toChapter: bookmark.chapterIndex, anchor: bookmark.anchorOffset)
    }

    // MARK: 书签

    func loadBookmarks() {
        guard let context, !bookID.isEmpty else { return }
        let bid = bookID
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.bookID == bid },
            sortBy: [SortDescriptor(\.chapterIndex), SortDescriptor(\.anchorOffset)]
        )
        bookmarks = (try? context.fetch(descriptor)) ?? []
    }

    func isCurrentPageBookmarked() -> Bool {
        bookmarkMatchingCurrentPosition() != nil
    }

    func toggleBookmark() {
        guard let context, !chapters.isEmpty, !bookID.isEmpty else { return }
        if let existing = bookmarkMatchingCurrentPosition() {
            context.delete(existing)
            try? context.save()
            loadBookmarks()
            return
        }
        let anchor = currentBookmarkAnchor
        let bookmark = Bookmark(
            bookID: bookID,
            chapterIndex: chapterIndex,
            anchorOffset: anchor,
            chapterTitle: chapterTitle,
            excerpt: BookSearchEngine.excerpt(from: chapterText, at: anchor)
        )
        context.insert(bookmark)
        try? context.save()
        loadBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        guard let context else { return }
        context.delete(bookmark)
        try? context.save()
        loadBookmarks()
    }

    private var currentBookmarkAnchor: Int {
        if readingMode == .scroll { return anchorOffset }
        return currentPage?.location ?? anchorOffset
    }

    private func bookmarkMatchingCurrentPosition() -> Bookmark? {
        if readingMode == .scroll {
            return bookmarks.first {
                $0.chapterIndex == chapterIndex && abs($0.anchorOffset - anchorOffset) <= 150
            }
        }
        guard let p = currentPage else { return nil }
        let end = p.location + max(p.length, 1)
        return bookmarks.first {
            $0.chapterIndex == chapterIndex && $0.anchorOffset >= p.location && $0.anchorOffset < end
        }
    }

    // MARK: 全文搜索

    func search(_ query: String) -> [BookSearchEngine.Match] {
        // 在线模式:检索已缓存的章节(边读边搜)
        if onlineMeta != nil {
            var payload: [(index: Int, title: String, text: String)] = []
            for (i, ch) in chapters.enumerated() {
                if let text = OnlineChapterStore.shared.chapterText(bookID: bookID, index: i) {
                    payload.append((i, ch.title, text))
                }
            }
            return BookSearchEngine.search(query: query, chapters: payload)
        }
        return BookSearchEngine.search(query: query, fullText: fullText, chapters: chapters)
    }

    // MARK: 阅读模式 / 点击分区

    func setReadingMode(_ mode: ReadingMode) {
        guard readingMode != mode else { return }
        readingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: ReaderPreferenceKeys.readingMode)
        if mode == .paged {
            pages = []
            pageIndex = 0
            paginate(keepAnchor: true)
        } else {
            saveProgress()
        }
    }

    func setTapZonePreset(_ preset: TapZonePreset) {
        guard tapZonePreset != preset else { return }
        tapZonePreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: ReaderPreferenceKeys.tapZone)
    }

    /// 滚动模式:位置上报(顶层字符偏移)
    func updateScrollPosition(_ offset: Int) {
        guard readingMode == .scroll else { return }
        anchorOffset = max(0, offset)
        saveProgress()
    }

    // MARK: 分页

    func paginate(size: CGSize? = nil, keepAnchor: Bool) {
        if let s = size, s.width > 1, s.height > 1 {
            lastSize = s
        }
        let contentSize = CGSize(
            width: lastSize.width - typography.horizontalMargin * 2,
            height: lastSize.height - typography.verticalMargin * 2
        )
        guard contentSize.width > 40, contentSize.height > 40, !chapterText.isEmpty else { return }

        if keepAnchor, readingMode == .paged, let p = currentPage {
            anchorOffset = p.location
        }
        let captured = anchorOffset
        generation += 1
        let gen = generation
        let text = chapterText
        let typo = typography

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (PaginationResult, Double) in
                let t0 = CFAbsoluteTimeGetCurrent()
                let result = PaginationEngine.paginate(text: text, typography: typo, pageSize: contentSize)
                return (result, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
            }.value
            guard gen == self.generation else { return }
            self.pages = outcome.0.pages
            self.pagingMillis = outcome.1
            if keepAnchor {
                self.pageIndex = PaginationEngine.pageIndex(containing: captured, in: outcome.0) ?? 0
            } else {
                self.pageIndex = min(self.pageIndex, max(0, outcome.0.pages.count - 1))
            }
            if self.readingMode == .paged, let p = self.currentPage {
                self.anchorOffset = p.location
            }
        }
    }

    // MARK: 翻页

    func slideToPage(_ index: Int) {
        guard !pages.isEmpty else { return }
        pageIndex = max(0, min(index, pages.count - 1))
        if let p = currentPage {
            anchorOffset = p.location
        }
        saveProgress()
    }

    func nextPage() {
        if pageIndex + 1 < pages.count {
            pageIndex += 1
            if let p = currentPage { anchorOffset = p.location }
            saveProgress()
        } else {
            nextChapter()
        }
    }

    func prevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
            if let p = currentPage { anchorOffset = p.location }
            saveProgress()
        } else {
            prevChapter()
        }
    }

    // MARK: 进度

    var readingProgress: Double {
        if readingMode == .scroll {
            let length = max(1, (chapterText as NSString).length)
            return min(1, max(0, Double(anchorOffset) / Double(length)))
        }
        guard !pages.isEmpty else { return 0 }
        return Double(pageIndex) / Double(pages.count)
    }

    func saveProgress() {
        guard let context, !bookID.isEmpty, !chapters.isEmpty else { return }
        let bid = bookID
        let percentage = (Double(chapterIndex) + readingProgress) / Double(chapters.count)

        let descriptor = FetchDescriptor<ReadingPosition>(
            predicate: #Predicate { $0.bookID == bid }
        )
        if let pos = (try? context.fetch(descriptor))?.first {
            pos.chapterIndex = chapterIndex
            pos.anchorOffset = anchorOffset
            pos.percentage = percentage
            pos.updatedAt = Date()
        } else {
            let pos = ReadingPosition(bookID: bid, chapterIndex: chapterIndex,
                                      anchorOffset: anchorOffset, percentage: percentage)
            context.insert(pos)
        }

        let bookDescriptor = FetchDescriptor<ShelfBook>(
            predicate: #Predicate { $0.id == bid }
        )
        if let book = (try? context.fetch(bookDescriptor))?.first {
            book.lastReadAt = Date()
        }
        try? context.save()
    }
}

// MARK: - 阅读页

struct ReaderScreen: View {
    let shelfBook: ShelfBook

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var model = ReaderModel()
    @StateObject private var scrollController = ScrollReaderController()
    @State private var showMenu = false
    @State private var showCatalog = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showBookmarks = false

    private var theme: ReaderTheme { ReaderTheme.theme(model.themeIndex) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            contentLayer
            if model.readingMode == .paged {
                tapLayer
            }
            if showMenu {
                menuOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showMenu)
        .sheet(isPresented: $showCatalog) {
            ChapterListSheet(chapters: model.chapters, current: model.chapterIndex) { idx in
                showCatalog = false
                model.jump(toChapter: idx)
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(model: model) { chapter, offset in
                showSearch = false
                model.jump(toChapter: chapter, anchor: offset)
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(model: model) { bookmark in
                showBookmarks = false
                model.jump(to: bookmark)
            }
        }
    }

    // MARK: 正文

    private var contentLayer: some View {
        GeometryReader { geo in
            ZStack {
                if model.loading {
                    ProgressView("正在打开…")
                } else if let e = model.errorText {
                    VStack(spacing: 12) {
                        Text(e)
                            .font(.system(size: 14))
                            .foregroundStyle(NFTheme.textSecondary)
                        Button("返回书架") { dismiss() }
                            .foregroundStyle(NFTheme.accent)
                    }
                } else if model.chapterLoading && model.chapterText.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView("正在获取章节…")
                        if model.isOnlineBook {
                            Text("在线书籍:边读边缓存,仅首次需要等待")
                                .font(.system(size: 12))
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                } else if model.chapterText.isEmpty, let e = model.chapterLoadError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 30))
                            .foregroundStyle(NFTheme.textSecondary.opacity(0.6))
                        Text("章节获取失败")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NFTheme.textPrimary)
                        Text(e)
                            .font(.system(size: 12))
                            .foregroundStyle(NFTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 18) {
                            Button("重试") { model.retryCurrentChapter() }
                                .foregroundStyle(NFTheme.accent)
                            Button("返回书架") { dismiss() }
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 30)
                } else if model.readingMode == .scroll {
                    ScrollReaderView(
                        text: model.chapterText,
                        typography: model.typography,
                        textColor: theme.uiText,
                        backgroundColor: theme.uiBackground,
                        startOffset: model.anchorOffset,
                        token: model.contentToken,
                        edgeFraction: model.tapZonePreset.edgeFraction,
                        controller: scrollController,
                        onTapZone: { handleTapZone($0) },
                        onPositionChange: { model.updateScrollPosition($0) },
                        onReachBottom: { model.nextChapter() }
                    )
                } else if let page = model.currentPage {
                    ReaderPageView(
                        attributed: PaginationEngine.attributedText(
                            model.chapterText,
                            typography: model.typography,
                            textColor: theme.uiText
                        ),
                        pageRange: page.range,
                        contentInsets: UIEdgeInsets(
                            top: model.typography.verticalMargin,
                            left: model.typography.horizontalMargin,
                            bottom: model.typography.verticalMargin,
                            right: model.typography.horizontalMargin
                        ),
                        backgroundColor: theme.uiBackground
                    )
                } else {
                    ProgressView("正在排版…")
                }
            }
            .onAppear {
                model.configure(bookID: shelfBook.id, context: context, size: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                model.paginate(size: newSize, keepAnchor: true)
            }
        }
    }

    // MARK: 点击分区

    private var tapLayer: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * model.tapZonePreset.edgeFraction)
                    .onTapGesture { handleTapZone(0) }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { handleTapZone(1) }
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * model.tapZonePreset.edgeFraction)
                    .onTapGesture { handleTapZone(2) }
            }
        }
        .ignoresSafeArea()
    }

    /// 点击分区统一入口:分页模式翻页 / 滚动模式按屏滚动 / 中间呼出菜单
    private func handleTapZone(_ zone: Int) {
        if showMenu {
            withAnimation {
                showMenu = false
                showSettings = false
            }
            return
        }
        let command = model.tapZonePreset.command(for: zone)
        switch command {
        case .previousPage:
            if model.readingMode == .scroll {
                if !scrollController.scroll(byFraction: -0.85), scrollController.textView != nil {
                    model.prevChapter()
                }
            } else {
                model.prevPage()
            }
        case .nextPage:
            if model.readingMode == .scroll {
                if !scrollController.scroll(byFraction: 0.85), scrollController.textView != nil {
                    model.nextChapter()
                }
            } else {
                model.nextPage()
            }
        case .toggleMenu:
            withAnimation { showMenu = true }
        }
    }

    // MARK: 菜单

    private var menuOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                        .frame(width: 40, height: 36, alignment: .leading)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(model.chapterTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NFTheme.textPrimary)
                        .lineLimit(1)
                    Text(model.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(NFTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    Button {
                        showMenu = false
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NFTheme.textPrimary)
                            .frame(width: 36, height: 36)
                    }
                    Button {
                        model.toggleBookmark()
                    } label: {
                        Image(systemName: model.isCurrentPageBookmarked() ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(model.isCurrentPageBookmarked() ? NFTheme.accent : NFTheme.textPrimary)
                            .frame(width: 36, height: 36)
                    }
                    Button {
                        showMenu = false
                        showCatalog = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NFTheme.textPrimary)
                            .frame(width: 36, height: 36, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)

            Spacer()

            if showSettings {
                ReaderSettingsPanel(model: model)
            }

            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if model.readingMode == .paged {
                HStack(spacing: 10) {
                    Text("\(model.pageIndex + 1)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(NFTheme.textSecondary)
                        .frame(width: 30, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(model.pageIndex + 1) },
                            set: { model.slideToPage(Int($0) - 1) }
                        ),
                        in: 1...Double(max(model.pageCount, 1)),
                        step: 1
                    )
                    .tint(NFTheme.accent)
                    Text("\(model.pageCount)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(NFTheme.textSecondary)
                        .frame(width: 34, alignment: .leading)
                }
            } else {
                ProgressView(value: model.readingProgress)
                    .tint(NFTheme.accent)
            }

            HStack {
                toolButton("上一章", "chevron.left.2") { model.prevChapter() }
                Spacer()
                toolButton("目录", "list.bullet") {
                    withAnimation { showMenu = false }
                    showCatalog = true
                }
                Spacer()
                toolButton("设置", "textformat.size") {
                    withAnimation { showSettings.toggle() }
                }
                Spacer()
                toolButton("下一章", "chevron.right.2") { model.nextChapter() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 30)
        .background(.ultraThinMaterial)
    }

    private func toolButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(NFTheme.textPrimary)
            .frame(width: 64)
        }
    }
}

// MARK: - 阅读设置面板

struct ReaderSettingsPanel: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("字号")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    Button {
                        model.typography.fontSize = max(13, model.typography.fontSize - 1)
                        model.schedulePaginate()
                    } label: {
                        Text("A-")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(NFTheme.textPrimary)
                            .frame(width: 44, height: 32)
                    }
                    Text("\(Int(model.typography.fontSize))")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(NFTheme.textPrimary)
                        .frame(width: 36)
                    Button {
                        model.typography.fontSize = min(28, model.typography.fontSize + 1)
                        model.schedulePaginate()
                    } label: {
                        Text("A+")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(NFTheme.textPrimary)
                            .frame(width: 44, height: 32)
                    }
                }

                HStack {
                    Text("字体")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    Picker("字体", selection: Binding(
                        get: { model.typography.fontName },
                        set: { model.typography.fontName = $0; model.schedulePaginate() }
                    )) {
                        ForEach(ReaderTypography.fontChoices, id: \.name) { choice in
                            Text(choice.display).tag(choice.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }

                typographySlider("行距", value: Binding(
                    get: { model.typography.lineSpacing },
                    set: { model.typography.lineSpacing = $0; model.schedulePaginate() }
                ), range: 2...20)
                typographySlider("段距", value: Binding(
                    get: { model.typography.paragraphSpacing },
                    set: { model.typography.paragraphSpacing = $0; model.schedulePaginate() }
                ), range: 0...30)
                typographySlider("缩进", value: Binding(
                    get: { model.typography.firstLineIndentChars },
                    set: { model.typography.firstLineIndentChars = $0; model.schedulePaginate() }
                ), range: 0...4)
                typographySlider("边距", value: Binding(
                    get: { model.typography.horizontalMargin },
                    set: { model.typography.horizontalMargin = $0; model.schedulePaginate() }
                ), range: 12...40)

                HStack {
                    Text("预设")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    ForEach(Self.presets.indices, id: \.self) { i in
                        let preset = Self.presets[i]
                        Button(preset.0) {
                            model.typography = preset.1
                            model.schedulePaginate()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NFTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(NFTheme.accentSoft)
                        .cornerRadius(8)
                    }
                }

                HStack {
                    Text("阅读模式")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    Picker("阅读模式", selection: Binding(
                        get: { model.readingMode },
                        set: { model.setReadingMode($0) }
                    )) {
                        ForEach(ReadingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                HStack {
                    Text("点按分区")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    Picker("点按分区", selection: Binding(
                        get: { model.tapZonePreset },
                        set: { model.setTapZonePreset($0) }
                    )) {
                        ForEach(TapZonePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 186)
                }

                HStack {
                    Text("主题")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    HStack(spacing: 14) {
                        ForEach(ReaderTheme.all) { t in
                            ZStack {
                                Circle()
                                    .fill(t.background)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(NFTheme.separator, lineWidth: 1))
                                if model.themeIndex == t.id {
                                    Circle()
                                        .stroke(NFTheme.accent, lineWidth: 2.5)
                                        .frame(width: 36, height: 36)
                                }
                            }
                            .onTapGesture { model.themeIndex = t.id }
                        }
                    }
                }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 400)
        }
        .background(.ultraThinMaterial)
    }

    private static let presets: [(String, ReaderTypography)] = [
        ("紧凑", .compactPreset),
        ("默认", .defaultPreset),
        ("宽松", .relaxedPreset),
    ]

    private func typographySlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(NFTheme.textSecondary)
                .frame(width: 48, alignment: .leading)
            Slider(value: value, in: range)
                .tint(NFTheme.accent)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(NFTheme.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - 目录面板

struct ChapterListSheet: View {
    let chapters: [StoredChapterMeta]
    let current: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(chapters, id: \.index) { ch in
                    Button {
                        onSelect(ch.index)
                    } label: {
                        HStack {
                            Text(ch.title)
                                .font(.system(size: 15))
                                .foregroundStyle(ch.index == current ? NFTheme.accent : NFTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .id(ch.index)
                }
                .listStyle(.plain)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
            .navigationTitle("目录（\(chapters.count)章）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(NFTheme.accent)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
