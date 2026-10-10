import SwiftUI

// MARK: - 全文搜索面板

/// 全书搜索:结果按章节 + 上下文展示,点击跳转
struct SearchSheet: View {
    @ObservedObject var model: ReaderModel
    let onSelect: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BookSearchEngine.Match] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(NFTheme.textSecondary)
                    TextField("搜索全书内容", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in
                            scheduleSearch(newValue)
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                }
                .padding(10)
                .background(NFTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .padding(14)

                Divider()

                if trimmedQuery.isEmpty {
                    ContentUnavailableView {
                        Label("搜索全书", systemImage: "text.magnifyingglass")
                    } description: {
                        Text("输入关键词,结果按章节与上下文展示。")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("没有找到", systemImage: "magnifyingglass")
                    } description: {
                        Text("没有与「\(trimmedQuery)」匹配的内容。")
                    }
                } else {
                    List {
                        Section("共 \(results.count) 条") {
                            ForEach(results) { match in
                                Button {
                                    onSelect(match.chapterIndex, match.chapterOffset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(match.chapterTitle)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(NFTheme.accent)
                                            .lineLimit(1)
                                        Text(match.snippet)
                                            .font(.system(size: 14))
                                            .foregroundStyle(NFTheme.textPrimary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(NFTheme.background)
            .navigationTitle("全文搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(NFTheme.accent)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { searchTask?.cancel() }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            results = []
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            results = model.search(keyword)
        }
    }
}

// MARK: - 书签面板

/// 书签列表:收藏当前页 / 跳转 / 删除
struct BookmarksSheet: View {
    @ObservedObject var model: ReaderModel
    let onSelect: (Bookmark) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.bookmarks.isEmpty {
                    ContentUnavailableView {
                        Label("还没有书签", systemImage: "bookmark")
                    } description: {
                        Text("在阅读页点右上角的书签图标,即可收藏当前页。")
                    }
                } else {
                    List {
                        ForEach(model.bookmarks) { bookmark in
                            Button {
                                onSelect(bookmark)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(bookmark.chapterTitle)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(NFTheme.accent)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(Self.formatter.string(from: bookmark.createdAt))
                                            .font(.system(size: 11))
                                            .foregroundStyle(NFTheme.textSecondary)
                                    }
                                    Text(bookmark.excerpt.isEmpty ? "(无摘录)" : bookmark.excerpt)
                                        .font(.system(size: 14))
                                        .foregroundStyle(NFTheme.textPrimary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    model.removeBookmark(bookmark)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(NFTheme.accent)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            model.loadBookmarks()
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
