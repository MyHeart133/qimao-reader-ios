import Foundation

/// Webnovel(阅文集团官方国际站)适配器
///
/// - 内容:官方授权中文网文英译版(如《蛊真人》官方英译 Reverend Insanity)
/// - 形态:发现型来源(搜索 + 详情 + 官方页面跳转;阅读与购买均跳转官方站)
/// - 数据:搜索页内嵌 schema.org JSON-LD;详情页 OpenGraph 元数据(均为官方公开页面数据)
/// - 搜索增强:内置常见中文书名 → 官方英译名映射,中文搜索词也能命中官方版本
final class WebnovelSource: ContentSource {
    let identifier = "webnovel"
    let displayName = "Webnovel(阅文官方)"
    let capabilities = SourceCapabilities.discoverOnly

    /// 常见中文书名 → Webnovel 官方英译名(命中后自动改用英译名搜索)
    static let aliasMap: [String: String] = [
        "蛊真人": "Reverend Insanity",
        "斗破苍穹": "Battle Through the Heavens",
        "凡人修仙传": "A Record of a Mortal's Journey to Immortality",
        "诡秘之主": "Lord of the Mysteries",
        "全职高手": "The King's Avatar",
        "斗罗大陆": "Soul Land",
        "盘龙": "Coiling Dragon",
        "星辰变": "Stellar Transformations",
        "大主宰": "The Great Ruler",
        "武动乾坤": "Martial Universe",
        "元尊": "Dragon Prince Yuan",
        "完美世界": "Perfect World",
        "圣墟": "The Sacred Ruins",
        "雪中悍刀行": "Sword Snow Stride",
    ]

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func search(_ query: String) async throws -> [SourceBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let term = Self.aliasMap[trimmed] ?? trimmed

        var comps = URLComponents(string: "https://www.webnovel.com/search")
        comps?.queryItems = [URLQueryItem(name: "keywords", value: term)]
        guard let url = comps?.url else {
            throw SourceError.network("搜索词无效")
        }
        let html = try await fetchHTML(url)
        return Self.parseSearchLD(html)
    }

    func fetchDetail(_ bookID: String) async throws -> SourceBook {
        guard let url = URL(string: "https://www.webnovel.com/book/\(bookID)") else {
            throw SourceError.network("书目标识无效")
        }
        let html = try await fetchHTML(url)
        return Self.parseBookPage(html, bookID: bookID)
    }

    private func fetchHTML(_ url: URL) async throws -> String {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceError.network("HTTP \(http.statusCode)")
            }
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } catch let e as SourceError {
            throw e
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
    }

    // MARK: - 解析

    /// 搜索页:提取 application/ld+json 中的 ItemList(schema.org)
    static func parseSearchLD(_ html: String) -> [SourceBook] {
        let blocks = allCaptures(
            pattern: "(?is)<script[^>]*application/ld\\+json[^>]*>(.*?)</script>",
            in: html
        )
        for block in blocks where block.contains("itemListElement") {
            guard let data = block.data(using: .utf8),
                  let list = try? JSONDecoder().decode(WebnovelItemList.self, from: data) else {
                continue
            }
            let books = (list.itemListElement ?? []).compactMap(Self.mapItem)
            if !books.isEmpty {
                return books
            }
        }
        return []
    }

    static func mapItem(_ item: WebnovelListItem) -> SourceBook? {
        guard let urlString = item.url, let name = item.name, !name.isEmpty else { return nil }
        guard let range = urlString.range(of: "/book/") else { return nil }
        let slugID = String(urlString[range.upperBound...])
        guard !slugID.isEmpty else { return nil }

        var cover = item.image
        if let c = cover, c.hasPrefix("http://") {
            cover = "https://" + c.dropFirst(7)
        }
        return SourceBook(
            sourceID: "webnovel",
            sourceBookID: slugID,
            title: name,
            author: item.author?.name ?? "",
            cover: cover,
            language: "en",
            summary: nil,
            subjects: [],
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: "https://www.webnovel.com/book/\(slugID)"
        )
    }

    /// 详情页:OpenGraph 元数据
    static func parseBookPage(_ html: String, bookID: String) -> SourceBook {
        let title = metaContent(html, property: "og:title") ?? bookID
        let summary = metaContent(html, property: "og:description")
        let cover = metaContent(html, property: "og:image")
        var author = metaContent(html, property: "og:novel:author") ?? ""
        if author.isEmpty {
            let blocks = allCaptures(
                pattern: "(?is)<script[^>]*application/ld\\+json[^>]*>(.*?)</script>",
                in: html
            )
            for block in blocks where block.contains("\"author\"") && !block.contains("\"WebSite\"") {
                if let name = firstCapture(
                    pattern: "\"author\"\\s*:\\s*\\{[^}]*\"name\"\\s*:\\s*\"([^\"]+)\"",
                    in: block
                ) {
                    author = name
                    break
                }
            }
        }
        return SourceBook(
            sourceID: "webnovel",
            sourceBookID: bookID,
            title: title,
            author: author,
            cover: cover,
            language: "en",
            summary: summary,
            subjects: [],
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: "https://www.webnovel.com/book/\(bookID)"
        )
    }

    static func metaContent(_ html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        if let v = firstCapture(pattern: "<meta[^>]+property=\"\(escaped)\"[^>]+content=\"([^\"]*)\"", in: html) {
            return EPUBParser.decodeEntities(v)
        }
        if let v = firstCapture(pattern: "<meta[^>]+content=\"([^\"]*)\"[^>]+property=\"\(escaped)\"", in: html) {
            return EPUBParser.decodeEntities(v)
        }
        return nil
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        EPUBParser.firstCapture(pattern: pattern, in: text)
    }

    private static func allCaptures(pattern: String, in text: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }
}

// MARK: - JSON 模型(schema.org ItemList)

struct WebnovelItemList: Decodable {
    let itemListElement: [WebnovelListItem]?
}

struct WebnovelListItem: Decodable {
    let url: String?
    let name: String?
    let image: String?
    let author: WebnovelPerson?
}

struct WebnovelPerson: Decodable {
    let name: String?
}
