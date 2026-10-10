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

    private var fullText = ""
    private var bookID = ""
    private var context: ModelContext?
    private var anchorOffset = 0
    private var lastSize: CGSize = .zero
    private var generation = 0
    private var configured = false

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
        let page = pages.isEmpty ? 0 : pageIndex + 1
        let ch = chapters.isEmpty ? 0 : chapterIndex + 1
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

    // MARK: 章节切换

    func enterChapter(index: Int, keepAnchor: Bool) {
        guard !chapters.isEmpty else { return }
        chapterIndex = max(0, min(index, chapters.count - 1))
        let meta = chapters[chapterIndex]
        let ns = fullText as NSString
        let loc = min(max(0, meta.location), ns.length)
        let len = min(max(0, meta.length), ns.length - loc)
        chapterText = ns.substring(with: NSRange(location: loc, length: len))
        if !keepAnchor {
            anchorOffset = 0
        }
        pageIndex = 0
        paginate(keepAnchor: keepAnchor)
        saveProgress()
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

        if keepAnchor, let p = currentPage {
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
            if let p = self.currentPage {
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

    private var progressWithinChapter: Double {
        guard !pages.isEmpty else { return 0 }
        return Double(pageIndex) / Double(pages.count)
    }

    func saveProgress() {
        guard let context, !bookID.isEmpty, !chapters.isEmpty else { return }
        let bid = bookID
        let percentage = (Double(chapterIndex) + progressWithinChapter) / Double(chapters.count)

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
    @State private var showMenu = false
    @State private var showCatalog = false
    @State private var showSettings = false

    private var theme: ReaderTheme { ReaderTheme.theme(model.themeIndex) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            contentLayer
            tapLayer
            if showMenu {
                menuOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showMenu)
        .onChange(of: model.typography) { _, _ in
            model.paginate(keepAnchor: true)
        }
        .sheet(isPresented: $showCatalog) {
            ChapterListSheet(chapters: model.chapters, current: model.chapterIndex) { idx in
                showCatalog = false
                model.jump(toChapter: idx)
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
                    .frame(width: geo.size.width * 0.28)
                    .onTapGesture { tapZone(0) }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { tapZone(1) }
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * 0.28)
                    .onTapGesture { tapZone(2) }
            }
        }
        .ignoresSafeArea()
    }

    private func tapZone(_ zone: Int) {
        if showMenu {
            withAnimation {
                showMenu = false
                showSettings = false
            }
            return
        }
        switch zone {
        case 0: model.prevPage()
        case 2: model.nextPage()
        default: withAnimation { showMenu = true }
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
                Button {
                    showCatalog = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NFTheme.textPrimary)
                        .frame(width: 40, height: 36, alignment: .trailing)
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
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("字号")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                    Button {
                        model.typography.fontSize = max(13, model.typography.fontSize - 1)
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
                    } label: {
                        Text("A+")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(NFTheme.textPrimary)
                            .frame(width: 44, height: 32)
                    }
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
        .background(.ultraThinMaterial)
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
