import Foundation

/// 书源注册表:新增/移除来源不需要改动书架与阅读器
final class SourceRegistry {
    static let shared = SourceRegistry()

    private(set) var sources: [ContentSource] = []

    private init() {
        register(GutendexSource())
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

        // 去重:同一来源内按 sourceBookID,跨来源按 标题+作者
        var seenKeys = Set<String>()
        var seenIDs = Set<String>()
        var merged: [SourceBook] = []
        for book in collected {
            let key = "\(book.title.lowercased())|\(book.author.lowercased())"
            if seenIDs.contains(book.id) { continue }
            if seenKeys.contains(key) { continue }
            seenIDs.insert(book.id)
            seenKeys.insert(key)
            merged.append(book)
        }
        return merged
    }
}
