import SwiftData
import SwiftUI

/// 书架:真实书籍列表(导入 / 下载后的书都在这里)
struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShelfBook.addedAt, order: .reverse) private var books: [ShelfBook]
    @State private var opened: ShelfBook?

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("书架空空如也", systemImage: "books.vertical")
                } description: {
                    Text("去「书库」搜索开放书库,或导入本地的 TXT / EPUB 文件。")
                }
            } else {
                List {
                    ForEach(books) { book in
                        Button {
                            opened = book
                        } label: {
                            ShelfRow(book: book)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("彻底删除", role: .destructive) {
                                LibraryService.deleteCompletely(book, context: context)
                            }
                            Button("移出书架") {
                                LibraryService.removeFromShelf(book, context: context)
                            }
                            .tint(.gray)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(NFTheme.background)
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $opened) { book in
            ReaderScreen(shelfBook: book)
        }
    }
}

struct ShelfRow: View {
    let book: ShelfBook

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(NFTheme.accentSoft)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(NFTheme.accent.opacity(0.7))
            }
            .frame(width: 52, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NFTheme.textPrimary)
                    .lineLimit(1)
                Text(book.author.isEmpty ? "未知作者" : book.author)
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(book.sourceID == "local-import" ? "本地导入" : book.sourceID)
                        .font(.system(size: 11))
                        .foregroundStyle(NFTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NFTheme.accentSoft)
                        .cornerRadius(4)
                    if let last = book.lastReadAt {
                        Text("最近阅读 " + Self.formatter.string(from: last))
                            .font(.system(size: 11))
                            .foregroundStyle(NFTheme.textSecondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NFTheme.textSecondary.opacity(0.4))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()
}
