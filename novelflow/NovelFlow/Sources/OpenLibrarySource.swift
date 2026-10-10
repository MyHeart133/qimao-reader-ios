import Foundation

/// Open Library(Internet Archive 开放书目)适配器
///
/// - 内容:全球书目元数据(数千万条,含部分中文书目)
/// - 形态:发现型来源(搜索 + 元数据 + 官方页面跳转)
/// - 接口:openlibrary.org 公开搜索 API(无需密钥)
final class OpenLibrarySource: ContentSource {
    let identifier = "openlibrary"
    let displayName = "Open Library"
    let capabilities = SourceCapabilities.discoverOnly

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func search(_ query: String) async throws -> [SourceBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var comps = URLComponents(string: "https://openlibrary.org/search.json")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,cover_i,language,subject"),
        ]
        guard let url = comps?.url else {
            throw SourceError.network("搜索词无效")
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceError.network("HTTP \(http.statusCode)")
            }
            let decoded = try JSONDecoder().decode(OLSearchResponse.self, from: data)
            return (decoded.docs ?? []).compactMap(Self.mapDoc)
        } catch let e as SourceError {
            throw e
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
    }

    static func mapDoc(_ doc: OLDoc) -> SourceBook? {
        guard let title = doc.title, !title.isEmpty else { return nil }
        var cover: String?
        if let coverID = doc.coverI {
            cover = "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        }
        var external: String?
        if let key = doc.key {
            external = "https://openlibrary.org\(key)"
        }
        return SourceBook(
            sourceID: "openlibrary",
            sourceBookID: doc.key ?? title,
            title: title,
            author: (doc.authorName ?? []).prefix(2).joined(separator: "; "),
            cover: cover,
            language: doc.language?.first,
            summary: nil,
            subjects: Array((doc.subject ?? []).prefix(6)),
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: external
        )
    }
}

struct OLSearchResponse: Decodable {
    let docs: [OLDoc]?
}

struct OLDoc: Decodable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let firstPublishYear: Int?
    let coverI: Int?
    let language: [String]?
    let subject: [String]?

    enum CodingKeys: String, CodingKey {
        case key, title, language, subject
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverI = "cover_i"
    }
}
