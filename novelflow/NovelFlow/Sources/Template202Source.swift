import Foundation

/// 「202 模板」聚合书源家族(202xs.com / 非凡中文 / 新笔趣阁 等同构镜像)
///
/// - 搜索:POST `/search.html`(表单字段 `s`)
/// - 详情:`/book/{id}/`(og:novel 元数据)
/// - 目录:`/book/{id}/{page}/` 分页目录(解析 `<select>` 的全部页,按章节 ID 数值升序重排)
/// - 正文:`/read/0/{id}/{cid}.html`;长章节分页 `{cid}_{k}.html`,
///   翻到越界页时站点会回退返回第 1 页(用「第N页」标题做终止判定)
final class Template202Source: ContentSource {
    struct Config {
        let id: String
        let name: String
        let base: String
    }

    let config: Config
    let identifier: String
    let displayName: String
    let capabilities = SourceCapabilities(
        search: true, metadata: true, onlineReading: true, fullDownload: true,
        requiresAccount: false, allowsOffline: true, allowsExport: true
    )

    private let session = WebSourceSupport.session(timeout: 25)

    init(_ config: Config) {
        self.config = config
        self.identifier = config.id
        self.displayName = config.name
    }

    // MARK: - ContentSource

    func search(_ query: String) async throws -> [SourceBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: config.base + "/search.html") else { return [] }
        let html = try await WebSourceSupport.fetchHTML(
            url, session: session,
            headers: ["Referer": config.base + "/"],
            method: "POST", form: ["s": trimmed]
        )
        return Self.parseSearch(html, sourceID: identifier, base: config.base)
    }

    func fetchDetail(_ bookID: String) async throws -> SourceBook {
        guard let url = URL(string: "\(config.base)/book/\(bookID)/") else {
            throw SourceError.network("书目标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        guard let book = Self.parseDetail(html, bookID: bookID, sourceID: identifier, base: config.base) else {
            throw SourceError.notFound
        }
        return book
    }

    func fetchChapterList(_ bookID: String) async throws -> [SourceChapter] {
        guard let firstURL = URL(string: "\(config.base)/book/\(bookID)/1/") else {
            throw SourceError.network("书目标识无效")
        }
        let firstHTML = try await WebSourceSupport.fetchHTML(firstURL, session: session)
        let pagePaths = Self.catalogPagePaths(from: firstHTML, bookID: bookID)
        var allChapters = Self.parseCatalog(firstHTML, bookID: bookID)

        // 其余目录页(小并发)
        let rest = pagePaths.filter { $0 != "/book/\(bookID)/1/" }
        let capped = Array(rest.prefix(300))
        let session = self.session
        let base = config.base
        for batch in stride(from: 0, to: capped.count, by: 4).map({ Array(capped[$0..<min($0 + 4, capped.count)]) }) {
            await withTaskGroup(of: [SourceChapter].self) { group in
                for path in batch {
                    group.addTask {
                        guard let url = URL(string: base + path) else { return [] }
                        guard let html = try? await WebSourceSupport.fetchHTML(url, session: session) else { return [] }
                        return Self.parseCatalog(html, bookID: bookID)
                    }
                }
                for await chapters in group {
                    allChapters.append(contentsOf: chapters)
                }
            }
        }

        // 去重 + 按章节 ID 数值升序(站内 ID 全局递增,与阅读顺序一致)
        let unique = Self.sortedUnique(allChapters)
        guard !unique.isEmpty else { throw SourceError.notFound }
        return unique
    }

    /// 去重并按章节 ID 数值升序重排(目录页可能混入「最新章节」倒序块)
    static func sortedUnique(_ chapters: [SourceChapter]) -> [SourceChapter] {
        var seen = Set<String>()
        var unique: [SourceChapter] = []
        for c in chapters where !seen.contains(c.id) {
            seen.insert(c.id)
            unique.append(c)
        }
        unique.sort { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
        return unique.enumerated().map { i, c in
            var c = c
            c.index = i + 1
            return c
        }
    }

    func fetchChapterContent(_ bookID: String, chapterID: String) async throws -> String {
        var pages: [String] = []
        var pageNumber = 0
        // 第 1 页无后缀;第 k 页(k>=2)为 `{cid}_{k-1}.html`;越界时站点回退第 1 页 → 用页码判定终止
        while pageNumber < 40 {
            let expected = pageNumber + 1
            let path = expected == 1
                ? "/read/0/\(bookID)/\(chapterID).html"
                : "/read/0/\(bookID)/\(chapterID)_\(expected - 1).html"
            guard let url = URL(string: config.base + path) else { break }
            let html: String
            do {
                html = try await WebSourceSupport.fetchHTML(url, session: session)
            } catch {
                break
            }
            guard let parsed = Self.parseChapterPage(html) else { break }
            if expected > 1, parsed.pageNumber != expected {
                break // 越界回退
            }
            if !parsed.text.isEmpty {
                pages.append(parsed.text)
            }
            if parsed.pageNumber != expected {
                break
            }
            pageNumber = expected
        }
        guard !pages.isEmpty else {
            throw SourceError.unsupported("该章正文为空(可能被删除或需要登录)")
        }
        return pages.joined(separator: "\n")
    }

    // MARK: - 解析(可测)

    static func parseSearch(_ html: String, sourceID: String, base: String) -> [SourceBook] {
        var books: [SourceBook] = []
        var seen = Set<String>()
        let pattern = "(?s)<span class=\"s2\"><a href=\"(/book/(\\d+)/)\"[^>]*>(.*?)</a></span>\\s*<span class=\"s5\">(.*?)</span>"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        for m in rx.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let path = ns.substring(with: m.range(at: 1))
            let bid = ns.substring(with: m.range(at: 2))
            let title = WebSourceSupport.cleanInline(ns.substring(with: m.range(at: 3)))
            let author = WebSourceSupport.cleanInline(ns.substring(with: m.range(at: 4)))
            guard !bid.isEmpty, !title.isEmpty, !seen.contains(bid) else { continue }
            seen.insert(bid)
            books.append(SourceBook(
                sourceID: sourceID,
                sourceBookID: bid,
                title: title,
                author: author,
                cover: nil,
                language: "zh",
                summary: nil,
                subjects: [],
                downloadCount: nil,
                downloadURL: nil,
                downloadFormat: nil,
                externalURL: base + path
            ))
        }
        return books
    }

    static func parseDetail(_ html: String, bookID: String, sourceID: String, base: String) -> SourceBook? {
        let title = WebSourceSupport.cleanInline(WebSourceSupport.metaContent(html, property: "og:title") ?? "")
        guard !title.isEmpty else { return nil }
        let author = WebSourceSupport.cleanInline(WebSourceSupport.metaContent(html, property: "og:novel:author") ?? "")
        let intro = WebSourceSupport.cleanInline(WebSourceSupport.metaContent(html, property: "og:description") ?? "")
        let coverRaw = WebSourceSupport.metaContent(html, property: "og:image") ?? ""
        let cover = WebSourceSupport.absoluteURL(coverRaw, base: base)
        var subjects: [String] = []
        if let category = WebSourceSupport.metaContent(html, property: "og:novel:category"), !category.isEmpty {
            subjects.append(WebSourceSupport.cleanInline(category))
        }
        if let status = WebSourceSupport.metaContent(html, property: "og:novel:status"), !status.isEmpty {
            subjects.append(WebSourceSupport.cleanInline(status))
        }
        if let latest = WebSourceSupport.metaContent(html, property: "og:novel:latest_chapter_name"), !latest.isEmpty {
            subjects.append("最新:\(WebSourceSupport.cleanInline(latest))")
        }
        return SourceBook(
            sourceID: sourceID,
            sourceBookID: bookID,
            title: title,
            author: author,
            cover: cover,
            language: "zh",
            summary: intro.isEmpty ? nil : intro,
            subjects: subjects,
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: "\(base)/book/\(bookID)/"
        )
    }

    /// 目录页里的全部分页路径(`<select>` 的 option)
    static func catalogPagePaths(from html: String, bookID: String) -> [String] {
        let pattern = "value=\"(/book/\(NSRegularExpression.escapedPattern(for: bookID))/\\d+/)\""
        var paths = WebSourceSupport.allCaptures(pattern: pattern, in: html)
        if !paths.contains("/book/\(bookID)/1/") {
            paths.insert("/book/\(bookID)/1/", at: 0)
        }
        return Array(Set(paths)).sorted {
            let a = Int($0.split(separator: "/").last ?? "") ?? 0
            let b = Int($1.split(separator: "/").last ?? "") ?? 0
            return a < b
        }
    }

    static func parseCatalog(_ html: String, bookID: String) -> [SourceChapter] {
        let pattern = "(?s)<a href=\"/read/0/\(NSRegularExpression.escapedPattern(for: bookID))/(\\d+)\\.html\"[^>]*>(.*?)</a>"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        var out: [SourceChapter] = []
        for m in rx.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let cid = ns.substring(with: m.range(at: 1))
            let title = WebSourceSupport.cleanInline(ns.substring(with: m.range(at: 2)))
            guard !cid.isEmpty, !title.isEmpty, !isButtonTitle(title) else { continue }
            out.append(SourceChapter(id: cid, index: 0, title: title, isFree: true))
        }
        return out
    }

    /// 目录页里的功能按钮(带图标链接,与真实章节 ID 冲突,必须剔除)
    static func isButtonTitle(_ title: String) -> Bool {
        ["立即阅读", "加入书架", "小说详情", "开始阅读", "查看全部"].contains(title)
    }

    struct ChapterPage {
        var pageNumber: Int
        var title: String
        var text: String
    }

    static func parseChapterPage(_ html: String) -> ChapterPage? {
        guard let h2Range = html.range(of: "<h2 class=\"chapter-title\">") else { return nil }
        let afterH2 = html[h2Range.upperBound...]
        let h2End = afterH2.range(of: "</h2>")?.upperBound ?? afterH2.startIndex
        let title = WebSourceSupport.cleanInline(String(afterH2[afterH2.startIndex..<h2End]))
        let pageNumber = Int(WebSourceSupport.firstCapture(pattern: "第(\\d+)页", in: title) ?? "1") ?? 1

        // 正文位于上导航(read_btn#1)与下导航(read_btn#2)之间
        let navMarker = "<div class=\"read_btn\">"
        guard let nav1 = html.range(of: navMarker, range: h2End..<html.endIndex),
              let nav1End = html.range(of: "</div>", range: nav1.upperBound..<html.endIndex) else {
            return nil
        }
        let bodyEnd: String.Index
        if let nav2 = html.range(of: navMarker, range: nav1End.upperBound..<html.endIndex) {
            bodyEnd = nav2.lowerBound
        } else if let tail = html.range(of: "<div class=\"phb_fm", range: nav1End.upperBound..<html.endIndex) {
            bodyEnd = tail.lowerBound
        } else {
            bodyEnd = html.endIndex
        }
        let body = String(html[nav1End.upperBound..<bodyEnd])
        let text = paragraphText(body)
        return ChapterPage(pageNumber: pageNumber, title: title, text: text)
    }

    /// 提取 `<p>` 段落文本,过滤站点广告行
    static func paragraphText(_ body: String) -> String {
        let paragraphs = WebSourceSupport.allCaptures(pattern: "(?s)<p[^>]*>(.*?)</p>", in: body)
            .map { WebSourceSupport.cleanInline($0) }
            .filter { !$0.isEmpty && !isAdLine($0) }
        return paragraphs.joined(separator: "\n")
    }

    static func isAdLine(_ line: String) -> Bool {
        line.contains("一秒记住") || line.contains("请记住本站") || line.contains("手机浏览器扫描")
    }
}

// MARK: - 同构镜像实例

extension Template202Source {
    static let mirrors: [Template202Source] = [
        Template202Source(Config(id: "202xs", name: "202小说网", base: "https://202xs.com")),
        Template202Source(Config(id: "ffzw", name: "非凡中文", base: "https://ffzw.cc")),
        Template202Source(Config(id: "xinbiqu", name: "新笔趣阁", base: "https://xinbiqu.org")),
    ]
}
