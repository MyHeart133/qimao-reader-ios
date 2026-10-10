import SwiftUI

/// 书架:阅读过/下载过的书,支持继续阅读
struct LibraryView: View {
    @ObservedObject private var shelf = ShelfStore.shared

    @State private var opening: QBook?
    @State private var openChapters: [QChapter] = []
    @State private var openIndex = 1
    @State private var showReader = false
    @State private var loadingID: String?
    @State private var errMsg: String?

    var body: some View {
        Group {
            if shelf.books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(shelf.books) { b in
                            ShelfRow(book: b, busy: loadingID == b.id) {
                                openBook(b)
                            } onDelete: {
                                shelf.remove(b.id)
                            }
                        }
                    }
                    .padding(14)
                }
                .background(QTheme.bg)
            }
        }
        .background(QTheme.bg)
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showReader) {
            if let b = opening {
                ReaderView(book: b, chapters: openChapters, startIndex: openIndex)
            }
        }
        .alert("打开失败", isPresented: Binding(
            get: { errMsg != nil },
            set: { if !$0 { errMsg = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errMsg ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 46))
                .foregroundColor(QTheme.textSub.opacity(0.4))
            Text("书架空空如也")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(QTheme.textSub)
            Text("去「找书」搜索并阅读第一本书吧")
                .font(.system(size: 13))
                .foregroundColor(QTheme.textSub.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QTheme.bg)
    }

    private func openBook(_ b: ShelfBook) {
        guard loadingID == nil else { return }
        loadingID = b.id
        Task {
            do {
                let chs = try await QimaoAPI.shared.catalog(b.id)
                guard !chs.isEmpty else {
                    errMsg = "该书暂无章节"
                    loadingID = nil
                    return
                }
                opening = QBook(
                    id: b.id,
                    title: b.title,
                    author: b.author,
                    intro: b.intro,
                    cover: b.cover,
                    subTitle: "",
                    isOver: false,
                    latestChapter: "",
                    tags: ""
                )
                openChapters = chs
                openIndex = max(1, min(b.lastChapterIndex, chs.count))
                showReader = true
            } catch {
                errMsg = error.localizedDescription
            }
            loadingID = nil
        }
    }
}

struct ShelfRow: View {
    let book: ShelfBook
    let busy: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                CoverImage(url: book.cover)
                    .frame(width: 64, height: 86)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(QTheme.textMain)
                        .lineLimit(1)
                    Text(book.author)
                        .font(.system(size: 13))
                        .foregroundColor(QTheme.textSub)
                        .lineLimit(1)

                    if book.chapterCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(min(book.lastChapterIndex, book.chapterCount)),
                                         total: Double(max(book.chapterCount, 1)))
                                .tint(QTheme.primary)
                            HStack(spacing: 6) {
                                Text("读到 第\(book.lastChapterIndex)章")
                                    .font(.system(size: 11))
                                    .foregroundColor(QTheme.textSub)
                                Text("·")
                                    .font(.system(size: 11))
                                    .foregroundColor(QTheme.textSub)
                                Text("共\(book.chapterCount)章")
                                    .font(.system(size: 11))
                                    .foregroundColor(QTheme.textSub)
                                if book.downloaded {
                                    TagChip(text: "已下载")
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 5) {
                        if busy {
                            ProgressView().scaleEffect(0.7)
                            Text("加载中…")
                                .font(.system(size: 12))
                                .foregroundColor(QTheme.textSub)
                        } else {
                            Image(systemName: "book.fill")
                                .font(.system(size: 11))
                                .foregroundColor(QTheme.primary)
                            Text(book.lastChapterIndex > 1 ? "继续阅读" : "开始阅读")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(QTheme.primary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .qCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("移出书架", systemImage: "trash")
            }
        }
    }
}
