import SwiftUI

struct SearchView: View {
    @State private var keyword = ""
    @State private var results: [QBook] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var searched = false

    private let hotWords = ["斗破苍穹", "十日终焉", "离婚后", "赘婿", "龙王传说", "重生"]

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ScrollView {
                LazyVStack(spacing: 10) {
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("搜索中…").font(.system(size: 14)).foregroundColor(QTheme.textSub)
                        }
                        .padding(.top, 40)
                    } else if let e = errorText {
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 28))
                                .foregroundColor(QTheme.textSub.opacity(0.6))
                            Text(e).font(.system(size: 13)).foregroundColor(QTheme.textSub)
                        }
                        .padding(.top, 60)
                    } else if !searched {
                        hotSection
                    } else if results.isEmpty {
                        Text("没有找到相关书籍")
                            .font(.system(size: 14))
                            .foregroundColor(QTheme.textSub)
                            .padding(.top, 60)
                    } else {
                        ForEach(results) { b in
                            NavigationLink(value: b) {
                                BookCard(book: b)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
            }
            .background(QTheme.bg)
        }
        .background(QTheme.bg)
        .navigationTitle("找书")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: QBook.self) { b in
            BookDetailView(book: b)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(QTheme.textSub)
                TextField("搜索书名、作者", text: $keyword)
                    .font(.system(size: 15))
                    .submitLabel(.search)
                    .onSubmit { doSearch() }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(QTheme.textSub.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white)
            .cornerRadius(19)

            Button {
                doSearch()
            } label: {
                Text("搜索")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(QTheme.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(QTheme.bg)
    }

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundColor(QTheme.primary)
                Text("大家都在搜").font(.system(size: 15, weight: .semibold)).foregroundColor(QTheme.textMain)
            }
            FlowTags(words: hotWords) { w in
                keyword = w
                doSearch()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .qCard()
        .padding(.top, 10)
    }

    private func doSearch() {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !loading else { return }
        loading = true
        errorText = nil
        searched = true

        Task {
            do {
                let list = try await QimaoAPI.shared.search(kw)
                results = list
            } catch {
                errorText = error.localizedDescription
                results = []
            }
            loading = false
        }
    }
}

/// 自动换行的标签组
struct FlowTags: View {
    let words: [String]
    let onTap: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 74), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(words, id: \.self) { w in
                Text(w)
                    .font(.system(size: 13))
                    .foregroundColor(QTheme.textMain)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(QTheme.bg)
                    .cornerRadius(8)
                    .onTapGesture { onTap(w) }
            }
        }
    }
}

/// 搜索结果卡片
struct BookCard: View {
    let book: QBook

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: book.cover)
                .frame(width: 64, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(QTheme.textMain)
                    .lineLimit(1)
                Text(book.author)
                    .font(.system(size: 13))
                    .foregroundColor(QTheme.textSub)
                Text(book.subTitle.isEmpty ? book.intro : book.subTitle)
                    .font(.system(size: 12))
                    .foregroundColor(QTheme.textSub)
                    .lineLimit(2)
                    .padding(.top, 1)
                if !book.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(book.tags.split(separator: ",").prefix(3), id: \.self) { t in
                            TagChip(text: String(t))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .qCard()
    }
}
