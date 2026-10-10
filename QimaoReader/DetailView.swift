import SwiftUI

struct BookDetailView: View {
    let book: QBook

    @State private var detail: QBook?
    @State private var chapters: [QChapter] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var showReader = false
    @State private var readIndex = 1
    @State private var expandIntro = false

    @ObservedObject private var dl = DownloadManager.shared

    private var current: QBook { detail ?? book }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                actionBar
                if dl.active {
                    downloadProgress
                }
                introSection
                catalogSection
            }
            .padding(14)
        }
        .background(QTheme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .fullScreenCover(isPresented: $showReader) {
            ReaderView(book: current, chapters: chapters, startIndex: readIndex)
        }
        .alert("下载完成", isPresented: Binding(
            get: { dl.finishedMessage != nil },
            set: { if !$0 { dl.finishedMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(dl.finishedMessage ?? "")
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(url: current.cover, corner: 8)
                .frame(width: 100, height: 134)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 7) {
                Text(current.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(QTheme.textMain)
                    .lineLimit(2)

                Text(current.author)
                    .font(.system(size: 13))
                    .foregroundColor(QTheme.textSub)

                if !current.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(current.tags.split(separator: ",").prefix(3), id: \.self) { t in
                            TagChip(text: String(t))
                        }
                    }
                }

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    Text(current.isOver ? "已完结" : "连载中")
                        .font(.system(size: 12))
                        .foregroundColor(QTheme.textSub)
                    if !current.latestChapter.isEmpty {
                        Text("最新：\(current.latestChapter)")
                            .font(.system(size: 12))
                            .foregroundColor(QTheme.textSub)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .qCard()
    }

    // MARK: 操作

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                readIndex = 1
                if !chapters.isEmpty { showReader = true }
            } label: {
                Text("开始阅读")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(QTheme.primary)
                    .cornerRadius(23)
            }
            .disabled(chapters.isEmpty)

            Button {
                dl.download(book: current, chapters: chapters)
            } label: {
                Text(dl.active ? "下载中…" : "下载全本")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(QTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 23)
                            .stroke(QTheme.primary, lineWidth: 1.2)
                    )
                    .cornerRadius(23)
            }
            .disabled(chapters.isEmpty || dl.active)
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: dl.progress)
                .tint(QTheme.primary)
            Text(dl.statusText)
                .font(.system(size: 12))
                .foregroundColor(QTheme.textSub)
                .lineLimit(1)
        }
        .padding(14)
        .qCard()
    }

    // MARK: 简介

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("简介")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(QTheme.textMain)
            Text(current.intro.isEmpty ? "暂无简介" : current.intro)
                .font(.system(size: 14))
                .foregroundColor(QTheme.textMain.opacity(0.85))
                .lineSpacing(4)
                .lineLimit(expandIntro ? nil : 5)
            if current.intro.count > 80 {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expandIntro.toggle() }
                } label: {
                    Text(expandIntro ? "收起" : "展开全部")
                        .font(.system(size: 13))
                        .foregroundColor(QTheme.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .qCard()
    }

    // MARK: 目录

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("目录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(QTheme.textMain)
                Spacer()
                if loading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("共 \(chapters.count) 章")
                        .font(.system(size: 12))
                        .foregroundColor(QTheme.textSub)
                }
            }
            .padding(14)

            if let e = errorText {
                Text(e)
                    .font(.system(size: 13))
                    .foregroundColor(QTheme.primary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }

            ForEach(chapters) { ch in
                Button {
                    readIndex = ch.index
                    showReader = true
                } label: {
                    HStack {
                        Text(ch.title)
                            .font(.system(size: 14))
                            .foregroundColor(QTheme.textMain)
                            .lineLimit(1)
                        Spacer()
                        Text("\(ch.words)字")
                            .font(.system(size: 11))
                            .foregroundColor(QTheme.textSub)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if ch.id != chapters.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .qCard()
    }

    // MARK: 加载

    private func loadAll() async {
        loading = true
        errorText = nil
        do {
            async let d = QimaoAPI.shared.detail(book.id)
            async let c = QimaoAPI.shared.catalog(book.id)
            let (dd, cc) = try await (d, c)
            detail = dd
            chapters = cc
        } catch {
            errorText = "加载失败：\(error.localizedDescription)"
        }
        loading = false
    }
}
