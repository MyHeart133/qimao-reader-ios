import SwiftUI

/// 换源:以当前书籍的标题在各书源中查找同一本书
///
/// 用途:某来源缺章/收费/排版差时,快速切到另一来源阅读;
/// 找到的替代版本可直接进入详情缓存全本。
struct SourceSwitchView: View {
    let book: SourceBook

    @State private var results: [SourceBook] = []
    @State private var loading = true
    @State private var note: String?
    @State private var sheetBook: SourceBook?

    var body: some View {
        Group {
            if loading {
                VStack(spacing: 12) {
                    ProgressView("正在搜索其它书源…")
                    Text("按书名在七猫 / 起点 / Webnovel 等来源中匹配")
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.textSecondary)
                }
            } else if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(NFTheme.textSecondary.opacity(0.5))
                    Text("未在其它书源找到同一本书")
                        .font(.system(size: 14))
                        .foregroundStyle(NFTheme.textSecondary)
                    if let note {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(NFTheme.textSecondary.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                List {
                    Section {
                        ForEach(results) { alt in
                            Button {
                                sheetBook = alt
                            } label: {
                                row(alt)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("找到 \(results.count) 个其它来源(点击查看并缓存)")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(NFTheme.background)
        .navigationTitle("换源")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $sheetBook) { alt in
            SourceBookDetailView(book: alt)
        }
    }

    private func row(_ alt: SourceBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(alt.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NFTheme.textPrimary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(alt.author.isEmpty ? "未知作者" : alt.author)
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let src = SourceRegistry.shared.source(withID: alt.sourceID) {
                    chip(src.displayName)
                    if alt.downloadURL != nil {
                        chip("可下载")
                    } else if src.capabilities.onlineReading {
                        chip("可缓存全本")
                    }
                }
            }
        }
        .padding(.vertical, 2)
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

    // MARK: - 匹配

    private func load() async {
        let key = WebSourceSupport.normalizedKey(book.title)
        guard key.count >= 2 else {
            note = "书名过短,无法跨源匹配"
            loading = false
            return
        }
        let all = await SourceRegistry.shared.searchAll(book.title)
        let authorKey = WebSourceSupport.normalizedKey(book.author)

        // 每个来源保留一个最佳匹配;同作者优先
        var picked: [String: (book: SourceBook, authorMatch: Bool)] = [:]
        for alt in all where alt.sourceID != book.sourceID {
            let altKey = WebSourceSupport.normalizedKey(alt.title)
            guard !altKey.isEmpty else { continue }
            let titleMatch = altKey == key
                || (altKey.count >= 2 && key.contains(altKey))
                || (key.count >= 2 && altKey.contains(key))
            guard titleMatch else { continue }
            let authorMatch = !authorKey.isEmpty
                && WebSourceSupport.normalizedKey(alt.author) == authorKey
            if let existing = picked[alt.sourceID] {
                if authorMatch && !existing.authorMatch {
                    picked[alt.sourceID] = (alt, true)
                }
            } else {
                picked[alt.sourceID] = (alt, authorMatch)
            }
        }

        results = picked.values
            .sorted { lhs, rhs in
                if lhs.authorMatch != rhs.authorMatch { return lhs.authorMatch }
                let lCap = lhs.book.downloadURL != nil
                    || (SourceRegistry.shared.source(withID: lhs.book.sourceID)?.capabilities.onlineReading ?? false)
                let rCap = rhs.book.downloadURL != nil
                    || (SourceRegistry.shared.source(withID: rhs.book.sourceID)?.capabilities.onlineReading ?? false)
                if lCap != rCap { return lCap }
                return lhs.book.sourceID < rhs.book.sourceID
            }
            .map { $0.book }
        loading = false
    }
}
