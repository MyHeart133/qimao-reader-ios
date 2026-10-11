import Foundation

/// 番茄小说适配器(fanqienovel.com 网页版公开页面)
///
/// - 详情:`/page/{bookId}` 服务端渲染状态(书名/作者/简介/封面/章节总数)
/// - 目录:`/api/reader/directory/detail`(公开 JSON,含全部章节)
/// - 正文:`/reader/{itemId}` 服务端渲染章节数据
///   —— 正文对常用字做了 PUA 替换,由 `FanqieFontMap` 反混淆
/// - 搜索:网页搜索接口需要客户端签名(未开放),本来源不提供搜索;
///   入口为「番茄热榜」与链接/ID 直达
final class FanqieSource: ContentSource {
    let identifier = "fanqie"
    let displayName = "番茄小说"
    let capabilities = SourceCapabilities(
        search: false, metadata: true, onlineReading: true, fullDownload: true,
        requiresAccount: false, allowsOffline: true, allowsExport: true
    )

    private let session = WebSourceSupport.session(timeout: 25)

    // MARK: - ContentSource

    func search(_ query: String) async throws -> [SourceBook] {
        // 网页搜索接口需要签名,保持空结果(能力声明 search=false,UI 不会展示入口)
        return []
    }

    func fetchDetail(_ bookID: String) async throws -> SourceBook {
        guard let url = URL(string: "https://fanqienovel.com/page/\(bookID)") else {
            throw SourceError.network("书目标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        guard let state = WebSourceSupport.extractState(from: html),
              let page = WebSourceSupport.dict(state["page"]),
              let book = Self.mapBookPage(page, bookID: bookID) else {
            throw SourceError.notFound
        }
        return book
    }

    func fetchChapterList(_ bookID: String) async throws -> [SourceChapter] {
        guard let url = URL(string: "https://fanqienovel.com/api/reader/directory/detail?bookId=\(bookID)") else {
            throw SourceError.network("书目标识无效")
        }
        let json = try await WebSourceSupport.fetchJSON(url, session: session)
        let chapters = Self.parseDirectory(json)
        guard !chapters.isEmpty else { throw SourceError.notFound }
        return chapters
    }

    func fetchChapterContent(_ bookID: String, chapterID: String) async throws -> String {
        guard let url = URL(string: "https://fanqienovel.com/reader/\(chapterID)") else {
            throw SourceError.network("章节标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        guard let state = WebSourceSupport.extractState(from: html) else {
            throw SourceError.decode("章节页结构异常")
        }
        return try Self.chapterContent(fromState: state)
    }

    /// 番茄热榜(公开接口,用于「全网书源」页浏览)
    func topRank(limit: Int = 30) async throws -> [SourceBook] {
        guard let url = URL(string:
            "https://fanqienovel.com/api/rank/recommend/list" +
            "?app_id=2503&rank_list_type=3&offset=0&limit=\(max(1, min(limit, 50)))&category_id=0") else {
            throw SourceError.network("请求参数无效")
        }
        let json = try await WebSourceSupport.fetchJSON(url, session: session)
        return Self.parseRankList(json)
    }

    // MARK: - 链接/ID 解析(可测)

    /// 从粘贴的链接或 ID 中识别番茄书籍标识
    /// - `/page/{bookId}` → 书籍 ID 直达
    /// - `/reader/{itemId}` → 章节 ID(需再解析为书籍 ID)
    static func resolveReference(from input: String) -> FanqieReference? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let id = WebSourceSupport.firstCapture(pattern: "/page/(\\d{10,25})", in: s) {
            return .book(id)
        }
        if let id = WebSourceSupport.firstCapture(pattern: "/reader/(\\d{10,25})", in: s) {
            return .chapter(id)
        }
        if WebSourceSupport.matches("^\\d{15,25}$", in: s) {
            return .book(s)
        }
        return nil
    }

    /// 章节 ID → 书籍 ID(抓一次章节页,取 chapterData.bookId)
    func resolveBookID(fromChapter chapterID: String) async throws -> String {
        guard let url = URL(string: "https://fanqienovel.com/reader/\(chapterID)") else {
            throw SourceError.network("章节标识无效")
        }
        let html = try await WebSourceSupport.fetchHTML(url, session: session)
        guard let state = WebSourceSupport.extractState(from: html),
              let reader = WebSourceSupport.dict(state["reader"]),
              let data = WebSourceSupport.dict(reader["chapterData"]) else {
            throw SourceError.notFound
        }
        let bid = WebSourceSupport.string(data["bookId"])
        guard !bid.isEmpty else { throw SourceError.notFound }
        return bid
    }

    // MARK: - 解析(可测)

    /// 书籍页状态 → SourceBook
    static func mapBookPage(_ page: [String: Any], bookID: String) -> SourceBook? {
        let rawTitle = WebSourceSupport.string(page["bookName"])
        let title = FanqieFontMap.decode(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let author = FanqieFontMap.decode(
            WebSourceSupport.string(page["authorName"]).isEmpty
                ? WebSourceSupport.string(page["author"])
                : WebSourceSupport.string(page["authorName"])
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let abstract = FanqieFontMap.decode(WebSourceSupport.string(page["abstract"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cover = WebSourceSupport.string(page["thumbUrl"])
        var subjects: [String] = []
        let total = WebSourceSupport.int(page["chapterTotal"]) ?? 0
        if total > 0 { subjects.append("共 \(total) 章") }
        if WebSourceSupport.string(page["status"]) == "1" { subjects.append("完结") }
        let latest = FanqieFontMap.decode(WebSourceSupport.string(page["lastChapterTitle"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !latest.isEmpty { subjects.append("最新:\(latest)") }
        return SourceBook(
            sourceID: "fanqie",
            sourceBookID: bookID,
            title: title,
            author: author,
            cover: cover.isEmpty ? nil : cover,
            language: "zh",
            summary: abstract.isEmpty ? nil : abstract,
            subjects: subjects,
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: "https://fanqienovel.com/page/\(bookID)"
        )
    }

    /// 目录 JSON → 章节列表
    static func parseDirectory(_ json: [String: Any]) -> [SourceChapter] {
        let data = WebSourceSupport.dict(json["data"]) ?? [:]
        var out: [SourceChapter] = []

        let volumes = WebSourceSupport.array(data["chapterListWithVolume"]) ?? []
        for volume in volumes {
            for item in WebSourceSupport.array(volume) ?? [] {
                guard let c = WebSourceSupport.dict(item) else { continue }
                let itemID = WebSourceSupport.string(c["itemId"])
                guard !itemID.isEmpty else { continue }
                var title = FanqieFontMap.decode(WebSourceSupport.string(c["title"]))
                title = WebSourceSupport.cleanInline(title)
                let needPay = WebSourceSupport.int(c["needPay"]) ?? 0
                let locked = WebSourceSupport.flag(c["isChapterLock"])
                out.append(SourceChapter(
                    id: itemID,
                    index: out.count + 1,
                    title: title.isEmpty ? "第\(out.count + 1)章" : title,
                    isFree: needPay == 0 && !locked
                ))
            }
        }

        if out.isEmpty {
            // 兜底:只有 itemIds 时生成占位标题
            let ids = WebSourceSupport.array(data["allItemIds"]) ?? []
            for (i, v) in ids.enumerated() {
                let itemID = WebSourceSupport.string(v)
                guard !itemID.isEmpty else { continue }
                out.append(SourceChapter(id: itemID, index: i + 1, title: "第\(i + 1)章", isFree: true))
            }
        }
        return out
    }

    /// 章节页状态 → 正文(已反混淆)
    static func chapterContent(fromState state: [String: Any]) throws -> String {
        guard let reader = WebSourceSupport.dict(state["reader"]),
              let data = WebSourceSupport.dict(reader["chapterData"]), !data.isEmpty else {
            throw SourceError.notFound
        }
        let html = WebSourceSupport.string(data["content"])
        guard !html.isEmpty else {
            if WebSourceSupport.flag(data["isChapterLock"]) || (WebSourceSupport.int(data["needPay"]) ?? 0) > 0 {
                throw SourceError.unsupported("该章需在番茄小说内购买/解锁,暂无法缓存")
            }
            throw SourceError.unsupported("该章暂无内容")
        }
        let decoded = FanqieFontMap.decode(html)
        let text = WebSourceSupport.plainText(fromHTML: decoded)
        guard !text.isEmpty else { throw SourceError.decode("章节正文为空") }
        return text
    }

    /// 热榜 JSON → SourceBook 列表
    static func parseRankList(_ json: [String: Any]) -> [SourceBook] {
        let data = WebSourceSupport.dict(json["data"])
        let list = WebSourceSupport.array(data?["list"]) ?? []
        return list.compactMap { item -> SourceBook? in
            guard let d = WebSourceSupport.dict(item) else { return nil }
            let id = WebSourceSupport.string(d["bookId"])
            let title = FanqieFontMap.decode(WebSourceSupport.string(d["bookName"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty else { return nil }
            let abstract = FanqieFontMap.decode(WebSourceSupport.string(d["abstract"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cover = WebSourceSupport.string(d["thumbUri"])
            let category = FanqieFontMap.decode(WebSourceSupport.string(d["category"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SourceBook(
                sourceID: "fanqie",
                sourceBookID: id,
                title: title,
                author: FanqieFontMap.decode(WebSourceSupport.string(d["author"]))
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                cover: cover.isEmpty ? nil : cover,
                language: "zh",
                summary: abstract.isEmpty ? nil : abstract,
                subjects: category.isEmpty ? [] : [category],
                downloadCount: nil,
                downloadURL: nil,
                downloadFormat: nil,
                externalURL: "https://fanqienovel.com/page/\(id)"
            )
        }
    }
}

enum FanqieReference: Equatable {
    case book(String)
    case chapter(String)
}
