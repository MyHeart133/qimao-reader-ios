import Foundation

/// 单个书源的一批搜索结果(流式聚合用)
struct SourceSearchBatch: Sendable {
    let sourceID: String
    let books: [SourceBook]
    let error: String?
}

/// 书源注册表:新增/移除来源不需要改动书架与阅读器
final class SourceRegistry {
    static let shared = SourceRegistry()

    /// 单源搜索超时(超过即跳过,不再拖慢整体)
    static let searchTimeout: Double = 12

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
        register(HetushuSource())
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

    // MARK: - 聚合搜索

    /// 流式聚合搜索:每个来源完成即产出一批结果(先返回先展示)
    ///
    /// - 各来源并发执行,单源超时 12 秒(超时静默跳过)
    /// - 调用方负责增量合并与去重(见 `dedupe`),或直接消费批次
    func searchStream(_ query: String) -> AsyncStream<SourceSearchBatch> {
        let sources = searchableSources
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: SourceSearchBatch.self) { group in
                    for source in sources {
                        group.addTask {
                            do {
                                let books = try await Self.withTimeout(seconds: Self.searchTimeout) {
                                    try await source.search(query)
                                }
                                return SourceSearchBatch(sourceID: source.identifier, books: books, error: nil)
                            } catch {
                                return SourceSearchBatch(
                                    sourceID: source.identifier,
                                    books: [],
                                    error: error.localizedDescription
                                )
                            }
                        }
                    }
                    for await batch in group {
                        continuation.yield(batch)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 多源聚合搜索(一次性收集,内部走流式)
    func searchAll(_ query: String) async -> [SourceBook] {
        var collected: [SourceBook] = []
        for await batch in searchStream(query) {
            collected.append(contentsOf: batch.books)
        }
        return Self.dedupe(collected)
    }

    /// 超时包装:operation 与计时器赛跑,先完成者胜
    static func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.1, seconds) * 1_000_000_000))
                throw SourceError.network("搜索超时")
            }
            guard let result = try await group.next() else {
                throw SourceError.network("搜索超时")
            }
            group.cancelAll()
            return result
        }
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
