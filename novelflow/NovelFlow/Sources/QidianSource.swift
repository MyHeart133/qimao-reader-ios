import Foundation

/// 起点中文网适配器(m.qidian.com 移动网页公开页面)
///
/// - 搜索:`/search?kw=...&page=N` 服务端渲染结果(书名/作者/分类/简介/封面)
/// - 详情:`/book/{bookId}` OpenGraph + JSON-LD
/// - 目录:`/book/{bookId}/catalog` 全部章节(含「免费」标记)
/// - 正文:`/chapter/{bookId}/{cid}` 免费章节可读;
///   VIP 章节由服务端标记 `lock-mask`,本来源不破解,缓存时跳过并如实说明
final class QidianSource: ContentSource {
    let identifier = "qidian"
    let displayName = "起点中文网"
    let capabilities = SourceCapabilities(
        search: true, metadata: true, onlineReading: true, fullDownload: true,
        requiresAccount: false, allowsOffline: true, allowsExport: true
    )

    private let session = WebSourceSupport.session(timeout: 25)

    // MARK: - ContentSource

    func search(_ query: String) async throws -> [SourceBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://m.qidian.com/search?kw=\(encoded)&page=1") else {
            throw SourceError.network("关键词无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        return Self.parseSearch(html)
    }

    func fetchDetail(_ bookID: String) async throws -> SourceBook {
        guard let url = URL(string: "https://m.qidian.com/book/\(bookID)/") else {
            throw SourceError.network("书目标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        let book = Self.parseDetail(html, bookID: bookID)
        guard !book.title.isEmpty else { throw SourceError.notFound }
        return book
    }

    func fetchChapterList(_ bookID: String) async throws -> [SourceChapter] {
        guard let url = URL(string: "https://m.qidian.com/book/\(bookID)/catalog") else {
            throw SourceError.network("书目标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        let chapters = Self.parseCatalog(html, bookID: bookID)
        guard !chapters.isEmpty else { throw SourceError.notFound }
        return chapters
    }

    func fetchChapterContent(_ bookID: String, chapterID: String) async throws -> String {
        guard let url = URL(string: "https://m.qidian.com/chapter/\(bookID)/\(chapterID)/") else {
            throw SourceError.network("章节标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        return try Self.chapterContent(fromChapterHTML: html)
    }

    // MARK: - 解析(可测)

    /// 搜索结果页 → 书列表
    static func parseSearch(_ html: String) -> [SourceBook] {
        var books: [SourceBook] = []
        var seen = Set<String>()
        let pattern = "(?s)<a class=\"_bookWrapper_[^\"]*\"[^>]*href=\"//m\\.qidian\\.com/chapter/(\\d+)/0/\"[^>]*>(.*?)</a>"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        let matches = rx.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let bid = ns.substring(with: m.range(at: 1))
            guard !seen.contains(bid) else { continue }
            let inner = ns.substring(with: m.range(at: 2))
            let title = WebSourceSupport.cleanInline(
                WebSourceSupport.firstCapture(pattern: "(?s)<h2[^>]*>(.*?)</h2>", in: inner) ?? ""
            )
            guard !title.isEmpty else { continue }
            seen.insert(bid)
            let author = WebSourceSupport.cleanInline(
                WebSourceSupport.firstCapture(pattern: "(?s)<p class=\"_searchBookAuthor_[^\"]*\">(.*?)</p>", in: inner) ?? ""
            )
            let desc = WebSourceSupport.cleanInline(
                WebSourceSupport.firstCapture(pattern: "(?s)<p class=\"_searchBookDesc_[^\"]*\">(.*?)</p>", in: inner) ?? ""
            )
            let tagBlock = WebSourceSupport.firstCapture(pattern: "(?s)<div class=\"_tags_[^\"]*\">(.*?)</div>", in: inner) ?? ""
            let tags = WebSourceSupport.allCaptures(pattern: "(?s)<p>(.*?)</p>", in: tagBlock)
                .map { WebSourceSupport.cleanInline($0) }
                .filter { !$0.isEmpty }
            books.append(SourceBook(
                sourceID: "qidian",
                sourceBookID: bid,
                title: title,
                author: author,
                cover: "https://bookcover.yuewen.com/qdbimg/349573/\(bid)/180",
                language: "zh",
                summary: desc.isEmpty ? nil : desc,
                subjects: tags,
                downloadCount: nil,
                downloadURL: nil,
                downloadFormat: nil,
                externalURL: "https://m.qidian.com/book/\(bid)/"
            ))
        }
        return books
    }

    /// 书籍详情页 → SourceBook
    static func parseDetail(_ html: String, bookID: String) -> SourceBook {
        let title = WebSourceSupport.cleanInline(ogContent(html, "og:title") ?? "")
        let desc = WebSourceSupport.cleanInline(ogContent(html, "og:description") ?? "")
        var author = WebSourceSupport.firstCapture(
            pattern: "\"author\"\\s*:\\s*\\{[^}]*\"name\"\\s*:\\s*\"([^\"]+)\"",
            in: html
        ) ?? ""
        author = WebSourceSupport.cleanInline(author)
        var subjects: [String] = []
        if let status = WebSourceSupport.firstCapture(
            pattern: "\"name\"\\s*:\\s*\"连载状态\"\\s*,\\s*\"value\"\\s*:\\s*\"([^\"]+)\"",
            in: html
        ) {
            subjects.append(status)
        }
        return SourceBook(
            sourceID: "qidian",
            sourceBookID: bookID,
            title: title,
            author: author,
            cover: "https://bookcover.yuewen.com/qdbimg/349573/\(bookID)/600",
            language: "zh",
            summary: desc.isEmpty ? nil : desc,
            subjects: subjects,
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: "https://m.qidian.com/book/\(bookID)/"
        )
    }

    /// 目录页 → 章节列表(含免费标记)
    static func parseCatalog(_ html: String, bookID: String) -> [SourceChapter] {
        var out: [SourceChapter] = []
        let pattern = "(?s)<a class=\"_chapterItem_[^\"]*\"[^>]*href=\"//m\\.qidian\\.com/chapter/(\\d+)/(\\d+)/\"[^>]*>(.*?)</a>"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        let matches = rx.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let bid = ns.substring(with: m.range(at: 1))
            guard bid == bookID else { continue }
            let cid = ns.substring(with: m.range(at: 2))
            let inner = ns.substring(with: m.range(at: 3))
            var title = WebSourceSupport.cleanInline(
                WebSourceSupport.firstCapture(pattern: "(?s)<h2[^>]*>(.*?)</h2>", in: inner) ?? ""
            )
            if title.isEmpty {
                // 从 title 属性兜底:「斗破苍穹 第一章 陨落的天才在线阅读」
                let rawTitle = WebSourceSupport.firstCapture(
                    pattern: "title=\"([^\"]*)\"",
                    in: ns.substring(with: m.range(at: 0))
                ) ?? ""
                title = WebSourceSupport.cleanInline(
                    rawTitle.replacingOccurrences(of: "在线阅读", with: "")
                )
            }
            guard !title.isEmpty else { continue }
            let isFree = inner.contains("免费")
            out.append(SourceChapter(id: cid, index: out.count + 1, title: title, isFree: isFree))
        }
        return out
    }

    /// 章节页 → 正文;VIP 章节(lock-mask)抛 unsupported
    static func chapterContent(fromChapterHTML html: String) throws -> String {
        guard let open = html.range(of: "<main id=\"c-") else {
            throw SourceError.decode("章节页结构异常")
        }
        guard let openEnd = html[open.lowerBound...].firstIndex(of: ">") else {
            throw SourceError.decode("章节页结构异常")
        }
        let openTag = html[open.lowerBound...openEnd]
        if openTag.contains("lock-mask") {
            throw SourceError.unsupported("起点 VIP 章节需订阅,暂无法缓存")
        }
        guard let close = html.range(of: "</main>", range: openEnd..<html.endIndex) else {
            throw SourceError.decode("章节页结构异常")
        }
        let body = String(html[html.index(after: openEnd)..<close.lowerBound])
        let paragraphs = WebSourceSupport.allCaptures(pattern: "(?s)<p[^>]*>(.*?)</p>", in: body)
            .map { WebSourceSupport.cleanInline($0) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else {
            throw SourceError.decode("章节正文为空")
        }
        return paragraphs.joined(separator: "\n")
    }

    // MARK: - 工具

    private static func ogContent(_ html: String, _ property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        if let v = WebSourceSupport.firstCapture(
            pattern: "<meta[^>]+property=\"\(escaped)\"[^>]+content=\"([^\"]*)\"",
            in: html
        ) {
            return EPUBParser.decodeEntities(v)
        }
        if let v = WebSourceSupport.firstCapture(
            pattern: "<meta[^>]+content=\"([^\"]*)\"[^>]+property=\"\(escaped)\"",
            in: html
        ) {
            return EPUBParser.decodeEntities(v)
        }
        return nil
    }
}
