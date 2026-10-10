import Foundation

/// Project Gutenberg 开放书库适配器(基于公开的 Gutendex API)
///
/// - 内容:7 万+ 本公共领域电子书(符合 Gutenberg 许可,允许下载与离线)
/// - 接口:gutendex.com(无需密钥,官方建议的开放元数据服务)
/// - 能力:搜索 / 元数据 / 整本下载(TXT 或 EPUB 直链)
final class GutendexSource: ContentSource {
    let identifier = "gutenberg"
    let displayName = "Gutenberg 开放书库"
    let capabilities = SourceCapabilities.openCatalog

    private let base = "https://gutendex.com"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func search(_ query: String) async throws -> [SourceBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/books?search=\(encoded)") else {
            throw SourceError.network("关键词无效")
        }
        let response: GutendexListResponse = try await fetchJSON(url)
        return (response.results ?? []).map(Self.mapBook)
    }

    func fetchDetail(_ bookID: String) async throws -> SourceBook {
        guard let url = URL(string: "\(base)/books/\(bookID)") else {
            throw SourceError.network("书目标识无效")
        }
        let book: GutendexBook = try await fetchJSON(url)
        return Self.mapBook(book)
    }

    // MARK: - 网络

    private func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceError.network("HTTP \(http.statusCode)")
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw SourceError.decode(error.localizedDescription)
            }
        } catch let e as SourceError {
            throw e
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
    }

    // MARK: - 映射

    static func mapBook(_ g: GutendexBook) -> SourceBook {
        // 优先 UTF-8 纯文本,其次任意 text/plain,再退 EPUB
        var downloadURL: String?
        var format: String?
        if let txt = g.formats?["text/plain; charset=utf-8"] {
            downloadURL = txt
            format = "txt"
        } else if let any = g.formats?.first(where: { $0.key.hasPrefix("text/plain") })?.value {
            downloadURL = any
            format = "txt"
        } else if let epub = g.formats?["application/epub+zip"] {
            downloadURL = epub
            format = "epub"
        }

        return SourceBook(
            sourceID: "gutenberg",
            sourceBookID: String(g.id),
            title: g.title,
            author: (g.authors ?? []).map(\.name).joined(separator: "; "),
            cover: g.formats?["image/jpeg"],
            language: g.languages?.first,
            summary: g.summaries?.first,
            subjects: Array((g.subjects ?? []).prefix(6)),
            downloadCount: g.downloadCount,
            downloadURL: downloadURL,
            downloadFormat: format,
            externalURL: "https://www.gutenberg.org/ebooks/\(g.id)"
        )
    }
}

// MARK: - Gutendex 响应模型

struct GutendexListResponse: Decodable {
    let count: Int?
    let results: [GutendexBook]?
}

struct GutendexBook: Decodable {
    let id: Int
    let title: String
    let authors: [GutendexAuthor]?
    let summaries: [String]?
    let subjects: [String]?
    let languages: [String]?
    let formats: [String: String]?
    let downloadCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, authors, summaries, subjects, languages, formats
        case downloadCount = "download_count"
    }
}

struct GutendexAuthor: Decodable {
    let name: String
}
