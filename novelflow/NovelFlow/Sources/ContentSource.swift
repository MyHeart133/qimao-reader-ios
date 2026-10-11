import Foundation

/// 来源能力声明:UI 只依据真实能力展示按钮,不显示假入口
struct SourceCapabilities: Equatable, Codable {
    var search: Bool
    var metadata: Bool
    var onlineReading: Bool
    var fullDownload: Bool
    var requiresAccount: Bool
    var allowsOffline: Bool
    var allowsExport: Bool

    /// 纯发现型来源(只可搜索/看元数据)
    static let discoverOnly = SourceCapabilities(
        search: true, metadata: true, onlineReading: false, fullDownload: false,
        requiresAccount: false, allowsOffline: false, allowsExport: false
    )

    /// 开放内容库(如 Project Gutenberg):搜索 + 下载 + 离线 + 导出
    static let openCatalog = SourceCapabilities(
        search: true, metadata: true, onlineReading: false, fullDownload: true,
        requiresAccount: false, allowsOffline: true, allowsExport: true
    )

    /// 网络小说书源(七猫/起点等):搜索 + 逐章阅读 + 整本缓存
    static let webNovel = SourceCapabilities(
        search: true, metadata: true, onlineReading: true, fullDownload: true,
        requiresAccount: false, allowsOffline: true, allowsExport: true
    )
}

/// 统一书籍模型(跨来源)
struct SourceBook: Identifiable, Equatable {
    var sourceID: String
    var sourceBookID: String
    var title: String
    var author: String
    var cover: String?
    var language: String?
    var summary: String?
    var subjects: [String]
    var downloadCount: Int?
    /// 直链下载地址
    var downloadURL: String?
    /// "txt" / "epub"
    var downloadFormat: String?
    var externalURL: String?

    var id: String { "\(sourceID):\(sourceBookID)" }
    var stableID: String { id }
}

struct SourceChapter: Identifiable, Equatable {
    var id: String
    var index: Int
    var title: String
    /// 来源站是否可直接读取(如起点目录中的「免费」标记)
    var isFree: Bool = true
}

enum SourceError: LocalizedError {
    case network(String)
    case decode(String)
    case notFound
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "网络错误：\(m)"
        case .decode(let m): return "数据解析失败：\(m)"
        case .notFound: return "未找到该内容"
        case .unsupported(let m): return m
        }
    }
}

/// 统一内容源接口。不支持的能力必须在 capabilities 中声明为 false,
/// 对应方法可以继续使用默认实现(抛出 unsupported)。
protocol ContentSource: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    var capabilities: SourceCapabilities { get }
    func search(_ query: String) async throws -> [SourceBook]
    func fetchDetail(_ bookID: String) async throws -> SourceBook
    func fetchChapterList(_ bookID: String) async throws -> [SourceChapter]
    func fetchChapterContent(_ bookID: String, chapterID: String) async throws -> String
}

extension ContentSource {
    func fetchDetail(_ bookID: String) async throws -> SourceBook {
        throw SourceError.unsupported("\(displayName) 暂不支持详情接口")
    }

    func fetchChapterList(_ bookID: String) async throws -> [SourceChapter] {
        throw SourceError.unsupported("\(displayName) 暂不支持逐章列表")
    }

    func fetchChapterContent(_ bookID: String, chapterID: String) async throws -> String {
        throw SourceError.unsupported("\(displayName) 暂不支持逐章读取")
    }
}
