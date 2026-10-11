import Foundation

/// 书源注册表:新增/移除来源不需要改动书架与阅读器
final class SourceRegistry {
    static let shared = SourceRegistry()

    private(set) var sources: [ContentSource] = []

    private init() {
        register(QimaoSource())
        register(FanqieSource())
        register(QidianSource())
        // 聚合镜像(202 模板家族 + 飘天文学 + 笔趣阁 365)
        for mirror in Template202Source.mirrors {
            register(mirror)
        }
        register(PiaotiaSource())
        register(Biquge365Source())
        register(GutendexSource())
        register(OpenLibrarySource())
        register(WebnovelSource())
    }

    func register(_ source: ContentSource) {
        guard !sources.contains(where: { $0.identifier == source.identifier }) else { return }
        sources.append(source)
    }

    func source(withID id: String) -> ContentSource? {
        sources.first { $0.identifier == id }
    }

    /// 具备搜索能力的来源
    var searchableSources: [ContentSource] {
        sources.filter { $0.capabilities.search }
    }

    /// 具备整本下载能力的来源
    var downloadableSources: [ContentSource] {
        sources.filter { $0.capabilities.fullDownload }
    }

    /// 多源聚合搜索:并发执行,失败来源静默跳过(结果仍标记来源)
    func searchAll(_ query: String) async -> [SourceBook] {
        let sources = searchableSources
        guard !sources.isEmpty else { return [] }

        var collected: [SourceBook] = []
        await withTaskGroup(of: [SourceBook].self) { group in
            for source in sources {
                group.addTask {
                    (try? await source.search(query)) ?? []
                }
            }
            for await books in group {
                collected.append(contentsOf: books)
            }
        }
        return Self.dedupe(collected)
    }

    /// 去重:标题+作者相同视为同一作品;优先保留「可下载」版本
    static func dedupe(_ books: [SourceBook]) -> [SourceBook] {
        var best: [String: SourceBook] = [:]
        var order: [String] = []
        for book in books {
            let key = "\(book.title.lowercased())|\(book.author.lowercased())"
            if let existing = best[key] {
                if existing.downloadURL == nil && book.downloadURL != nil {
                    best[key] = book
                }
                continue
            }
            best[key] = book
            order.append(key)
        }
        return order.compactMap { best[$0] }
    }
}
