import SwiftUI

/// 仿七猫阅读器:沉浸阅读 + 点击分区翻章 + 呼出菜单(进度/目录/设置)
struct ReaderView: View {
    let book: QBook
    let chapters: [QChapter]

    @State private var index: Int
    @State private var text = ""
    @State private var loading = true
    @State private var errorText: String?
    @State private var showMenu = false
    @State private var showSettings = false
    @State private var showCatalog = false
    @State private var themeIndex = 0
    @State private var fontSize: CGFloat = 18
    @State private var sliderValue: Double = 1

    @Environment(\.dismiss) private var dismiss

    init(book: QBook, chapters: [QChapter], startIndex: Int) {
        self.book = book
        self.chapters = chapters
        let s = chapters.isEmpty ? 1 : max(1, min(startIndex, chapters.count))
        _index = State(initialValue: s)
        _sliderValue = State(initialValue: Double(s))
    }

    private var theme: QTheme.ReaderTheme { QTheme.readerTheme(themeIndex) }

    private var currentChapter: QChapter? {
        guard index >= 1 && index <= chapters.count else { return nil }
        return chapters[index - 1]
    }

    private var chapterTitle: String { currentChapter?.title ?? book.title }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            content

            tapLayer

            if showMenu {
                menuOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showMenu)
        .task(id: index) { await load() }
        .sheet(isPresented: $showCatalog) {
            CatalogSheet(chapters: chapters, current: index) { i in
                showCatalog = false
                jump(to: i)
            }
        }
    }

    // MARK: 正文

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(chapterTitle)
                    .font(.system(size: fontSize + 3, weight: .semibold))
                    .foregroundColor(theme.text)
                    .padding(.top, 26)
                    .padding(.bottom, 16)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                } else if let e = errorText {
                    VStack(spacing: 12) {
                        Text(e)
                            .font(.system(size: 14))
                            .foregroundColor(theme.text.opacity(0.7))
                        Button("点击重试") {
                            Task { await load() }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(QTheme.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    Text(text)
                        .font(.system(size: fontSize))
                        .lineSpacing(fontSize * 0.55)
                        .foregroundColor(theme.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(index)
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
        case 0: prevChapter()
        case 2: nextChapter()
        default:
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
                        .foregroundColor(QTheme.textMain)
                        .frame(width: 40, height: 36, alignment: .leading)
                }
                Spacer()
                Text(chapterTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(QTheme.textMain)
                    .lineLimit(1)
                Spacer()
                Button {
                    showCatalog = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(QTheme.textMain)
                        .frame(width: 40, height: 36, alignment: .trailing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)

            Spacer()

            if showSettings {
                settingsPanel
            }

            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.system(size: 12))
                    .foregroundColor(QTheme.textSub)
                    .frame(width: 34, alignment: .trailing)
                Slider(value: $sliderValue, in: 1...Double(max(chapters.count, 1)), step: 1) { editing in
                    if !editing {
                        jump(to: Int(sliderValue))
                    }
                }
                .tint(QTheme.primary)
                Text("\(chapters.count)")
                    .font(.system(size: 12))
                    .foregroundColor(QTheme.textSub)
                    .frame(width: 44, alignment: .leading)
            }

            HStack {
                toolButton("上一章", "chevron.left.2") { prevChapter() }
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
                toolButton("下一章", "chevron.right.2") { nextChapter() }
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
            .foregroundColor(QTheme.textMain)
            .frame(width: 64)
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("字号")
                        .font(.system(size: 13))
                        .foregroundColor(QTheme.textSub)
                    Spacer()
                    Button {
                        if fontSize > 14 { fontSize -= 1 }
                    } label: {
                        Text("A-")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(QTheme.textMain)
                            .frame(width: 44, height: 32)
                    }
                    Text("\(Int(fontSize))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(QTheme.textMain)
                        .frame(width: 36)
                    Button {
                        if fontSize < 26 { fontSize += 1 }
                    } label: {
                        Text("A+")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(QTheme.textMain)
                            .frame(width: 44, height: 32)
                    }
                }

                HStack {
                    Text("背景")
                        .font(.system(size: 13))
                        .foregroundColor(QTheme.textSub)
                    Spacer()
                    HStack(spacing: 14) {
                        ForEach(QTheme.readerThemes) { t in
                            ZStack {
                                Circle()
                                    .fill(t.bg)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 0.8))
                                if themeIndex == t.id {
                                    Circle()
                                        .stroke(QTheme.primary, lineWidth: 2.5)
                                        .frame(width: 36, height: 36)
                                }
                                if t.isDark {
                                    Image(systemName: "moon.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.75))
                                }
                            }
                            .onTapGesture { themeIndex = t.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: 逻辑

    private func prevChapter() { jump(to: index - 1) }

    private func nextChapter() { jump(to: index + 1) }

    private func jump(to i: Int) {
        guard !chapters.isEmpty else { return }
        let n = max(1, min(i, chapters.count))
        if n != index {
            index = n
        }
        sliderValue = Double(n)
        withAnimation {
            showMenu = false
            showSettings = false
        }
    }

    private func load() async {
        guard let ch = currentChapter else { return }
        loading = true
        errorText = nil
        do {
            let t = try await QimaoAPI.shared.chapterText(book.id, chapterID: ch.id)
            text = t

            if ShelfStore.shared.book(book.id) == nil {
                ShelfStore.shared.upsert(ShelfBook(
                    id: book.id,
                    title: book.title,
                    author: book.author,
                    cover: book.cover,
                    intro: book.intro,
                    chapterCount: chapters.count,
                    downloaded: false,
                    savedName: "",
                    lastChapterIndex: index,
                    updatedAt: Date()
                ))
            } else {
                ShelfStore.shared.updateProgress(bookID: book.id, chapterIndex: index)
            }
        } catch {
            errorText = "加载失败：\(error.localizedDescription)"
        }
        loading = false
    }
}

// MARK: - 目录面板

struct CatalogSheet: View {
    let chapters: [QChapter]
    let current: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(chapters) { ch in
                    Button {
                        onSelect(ch.index)
                    } label: {
                        HStack {
                            Text(ch.title)
                                .font(.system(size: 15))
                                .foregroundColor(ch.index == current ? QTheme.primary : QTheme.textMain)
                                .lineLimit(1)
                            Spacer()
                            Text("\(ch.words)字")
                                .font(.system(size: 12))
                                .foregroundColor(QTheme.textSub)
                        }
                    }
                    .buttonStyle(.plain)
                    .id(ch.index)
                }
                .listStyle(.plain)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
            .navigationTitle("目录（\(chapters.count)章）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(QTheme.primary)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
