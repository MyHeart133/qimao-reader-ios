import Foundation
import SwiftData

/// 章节目录型书源的「整本缓存」管线
///
/// 职责:
/// - 拉取章节目录 → 逐章抓取正文(小并发 + 重试)→ 分章落盘(可断点续传)
/// - 全部完成后组装全文 → BookContentStore → 书架入库(与本地书籍同一阅读管线)
/// - 遇到来源站限制(如起点 VIP)时如实截断,已缓存部分照常入库
///
/// 与 DownloadManager 的分工:
/// - DownloadManager 负责「直链文件」来源(单 URL 传输)
/// - 本类负责「逐章接口」来源(多次请求 + 组装),状态独立持久化
@MainActor
final class ChapterCacheManager: ObservableObject {
    static let shared = ChapterCacheManager()

    // MARK: - 模型

    struct ChapterRef: Codable, Equatable {
        var id: String
        var title: String
        var isFree: Bool
    }

    struct Progress: Codable, Equatable {
        var state: DownloadState = .queued
        var total: Int = 0
        var done: Int = 0
        var failed: Int = 0
        /// 首个被来源站限制(锁定)的章节下标
        var lockedAt: Int? = nil
        var message: String? = nil
        var importedBookID: String? = nil
        var updatedAt: Date = Date()

        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(1, max(0, Double(done) / Double(total)))
        }

        var statusText: String {
            switch state {
            case .queued: return "等待中"
            case .downloading: return "缓存中 \(done)/\(total) 章"
            case .paused: return "已暂停 \(done)/\(total) 章"
            case .completed: return "已完成 \(done)/\(total) 章"
            case .failed: return "失败"
            case .cancelled: return "已取消"
            }
        }
    }

    struct Meta: Codable {
        var stableID: String
        var title: String
        var author: String
        var summary: String?
        var sourceID: String
        var sourceBookID: String
        var chapters: [ChapterRef]
        var progress: Progress
    }

    // MARK: - 状态

    @Published private(set) var progress: [String: Progress] = [:]

    private var metas: [String: Meta] = [:]
    private var runners: [String: Task<Void, Never>] = [:]
    private var context: ModelContext?
    private let fm = FileManager.default

    private init() {
        loadAll()
    }

    func attach(context: ModelContext) {
        self.context = context
    }

    // MARK: - 查询

    func state(for book: SourceBook) -> Progress? {
        progress[book.stableID]
    }

    func isBusy(_ book: SourceBook) -> Bool {
        guard let st = progress[book.stableID] else { return false }
        return st.state == .downloading || st.state == .queued
    }

    var activeCount: Int {
        progress.values.filter { $0.state == .downloading || $0.state == .queued }.count
    }

    // MARK: - 入口操作

    /// 开始/继续缓存(已完成的书可再次触发以补齐失败章节)
    func enqueue(_ book: SourceBook) {
        let id = book.stableID
        guard runners[id] == nil else { return }
        var meta = metas[id] ?? Meta(
            stableID: id,
            title: book.title,
            author: book.author,
            summary: book.summary,
            sourceID: book.sourceID,
            sourceBookID: book.sourceBookID,
            chapters: [],
            progress: Progress()
        )
        meta.title = book.title
        meta.author = book.author
        meta.summary = book.summary
        meta.progress.state = .queued
        meta.progress.message = nil
        meta.progress.failed = 0
        metas[id] = meta
        progress[id] = meta.progress
        persist(id)
        start(id)
    }

    func pause(_ book: SourceBook) {
        let id = book.stableID
        runners[id]?.cancel()
        runners[id] = nil
        guard var meta = metas[id] else { return }
        guard meta.progress.state == .downloading || meta.progress.state == .queued else { return }
        meta.progress.state = .paused
        meta.progress.message = "已暂停,可继续缓存"
        meta.progress.updatedAt = Date()
        metas[id] = meta
        progress[id] = meta.progress
        persist(id)
    }

    func resume(_ book: SourceBook) {
        guard var meta = metas[book.stableID],
              meta.progress.state == .paused || meta.progress.state == .failed else { return }
        meta.progress.state = .queued
        meta.progress.message = nil
        metas[book.stableID] = meta
        progress[book.stableID] = meta.progress
        persist(book.stableID)
        start(book.stableID)
    }

    /// 取消并清除已缓存的中间文件
    func cancel(_ book: SourceBook) {
        let id = book.stableID
        runners[id]?.cancel()
        runners[id] = nil
        metas[id] = nil
        progress[id] = nil
        try? fm.removeItem(at: directory(for: id))
    }

    // MARK: - 执行

    private func start(_ id: String) {
        runners[id]?.cancel()
        guard var meta = metas[id] else { return }
        meta.progress.state = .downloading
        meta.progress.updatedAt = Date()
        metas[id] = meta
        progress[id] = meta.progress
        persist(id)
        runners[id] = Task { [weak self] in
            guard let self else { return }
            await self.execute(id: id)
        }
    }

    private func execute(id: String) async {
        defer { runners[id] = nil }
        guard var meta = metas[id],
              let source = SourceRegistry.shared.source(withID: meta.sourceID) else {
            markFailed(id, message: "书源未注册")
            return
        }

        do {
            // 1) 章节目录(失败中断,可重试)
            if meta.chapters.isEmpty {
                let list = try await source.fetchChapterList(meta.sourceBookID)
                guard !list.isEmpty else { throw SourceError.notFound }
                meta.chapters = list.map { ChapterRef(id: $0.id, title: $0.title, isFree: $0.isFree) }
                meta.progress.total = list.count
                metas[id] = meta
                progress[id] = meta.progress
                persist(id)
            }
            if Task.isCancelled { return }

            // 2) 逐章抓取(4 并发小批量,断点续传)
            let total = meta.chapters.count
            let firstLocked = meta.chapters.firstIndex { !$0.isFree }
            let limit = firstLocked ?? total
            if firstLocked != nil {
                meta.progress.lockedAt = firstLocked
            }

            var doneCount = (0..<limit).filter { fm.fileExists(atPath: chapterFile(id, $0).path) }.count
            meta.progress.done = doneCount
            progress[id] = meta.progress

            var pending: [Int] = []
            for i in 0..<limit where !fm.fileExists(atPath: chapterFile(id, i).path) {
                pending.append(i)
            }

            let batchSize = 4
            var cursor = 0
            while cursor < pending.count {
                if Task.isCancelled { return }
                let batch = Array(pending[cursor..<min(cursor + batchSize, pending.count)])
                cursor += batch.count

                var lockedIndex: Int? = nil
                await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
                    for idx in batch {
                        let chapter = meta.chapters[idx]
                        let bookID = meta.sourceBookID
                        group.addTask {
                            do {
                                let text = try await Self.fetchWithRetry(source: source, bookID: bookID, chapter: chapter)
                                return (idx, .success(text))
                            } catch {
                                return (idx, .failure(error))
                            }
                        }
                    }
                    for await (idx, result) in group {
                        if Task.isCancelled { return }
                        switch result {
                        case .success(let text):
                            let url = self.chapterFile(id, idx)
                            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                                doneCount += 1
                            } else {
                                meta.progress.failed += 1
                            }
                        case .failure(let error):
                            if let sourceError = error as? SourceError, case .unsupported = sourceError {
                                if lockedIndex == nil || idx < lockedIndex! { lockedIndex = idx }
                            } else if error is CancellationError {
                                // 暂停/取消:状态已由对应操作更新
                            } else {
                                meta.progress.failed += 1
                            }
                        }
                    }
                }
                if Task.isCancelled { return }

                meta.progress.done = doneCount
                meta.progress.updatedAt = Date()
                if let locked = lockedIndex {
                    meta.progress.lockedAt = locked
                }
                metas[id] = meta
                progress[id] = meta.progress
                persist(id)

                if lockedIndex != nil { break }
            }
            if Task.isCancelled { return }

            // 3) 组装 + 入库
            try await finish(id: id, meta: meta)
        } catch is CancellationError {
            // 暂停/取消路径,不标失败
        } catch {
            markFailed(id, message: error.localizedDescription)
        }
    }

    private nonisolated static func fetchWithRetry(
        source: ContentSource,
        bookID: String,
        chapter: ChapterRef
    ) async throws -> String {
        var lastError: Error = SourceError.network("未知错误")
        for attempt in 0..<2 {
            do {
                return try await source.fetchChapterContent(bookID, chapterID: chapter.id)
            } catch let e as SourceError {
                if case .unsupported = e { throw e }
                lastError = e
            } catch {
                lastError = error
            }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
        throw lastError
    }

    // MARK: - 组装与入库

    private func finish(id: String, meta: Meta) async throws {
        guard let ctx = context else {
            throw SourceError.unsupported("应用数据上下文未就绪")
        }
        let (text, written) = Self.assembleText(meta: meta, directory: directory(for: id))
        guard written > 0 else {
            throw SourceError.decode("没有抓到任何章节内容,请稍后重试")
        }

        let intro = Self.introText(meta: meta, written: written)
        var updated = meta

        if let existingID = meta.progress.importedBookID, Self.shelfBook(id: existingID, context: ctx) != nil {
            // 已有书架记录 → 覆盖内容(补齐/更新)
            let textToSave = text
            try await Task.detached(priority: .userInitiated) { () throws -> Void in
                _ = try BookContentStore.shared.save(text: textToSave, bookID: existingID)
            }.value
            if let book = Self.shelfBook(id: existingID, context: ctx) {
                book.intro = intro
                book.contentSignature = "chapters:\(written)"
            }
            try? ctx.save()
        } else {
            let imported = ImportedBook(
                id: UUID().uuidString,
                title: meta.title,
                author: meta.author,
                text: text,
                format: "txt",
                originalFileName: meta.title + ".txt"
            )
            let book = try LibraryService.addImported(imported, sourceID: meta.sourceID, context: ctx)
            book.intro = intro
            book.contentSignature = "chapters:\(written)"
            try? ctx.save()
            updated.progress.importedBookID = book.id
        }

        updated.progress.state = .completed
        updated.progress.done = written
        updated.progress.message = Self.completionNote(meta: updated, written: written)
        updated.progress.updatedAt = Date()
        metas[id] = updated
        progress[id] = updated.progress
        persist(id)

        // 完整缓存 → 清理分章中间文件(保留 meta 以支持后续「重新缓存」检查)
        if updated.progress.lockedAt == nil && updated.progress.failed == 0 {
            try? fm.removeItem(at: chaptersDirectory(for: id))
        }
    }

    private func markFailed(_ id: String, message: String) {
        guard var meta = metas[id] else { return }
        meta.progress.state = .failed
        meta.progress.message = message
        meta.progress.updatedAt = Date()
        metas[id] = meta
        progress[id] = meta.progress
        persist(id)
    }

    // MARK: - 组装(可测)

    /// 章节标题规范化:保证组装文本能被 ChapterParser 正确切章
    static func normalizedHeading(index: Int, title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "第\(index + 1)章" }
        let patterns = [
            "^第[0-9零一二三四五六七八九十百千万两]+[章节回卷集部篇]",
            "^(序章|序言|楔子|引子|尾声|后记|番外|终章)",
            "^(Chapter|CHAPTER|chapter)[ 　0-9IVXLCDM]",
        ]
        for p in patterns where WebSourceSupport.matches(p, in: t) {
            return t
        }
        return "第\(index + 1)章 \(t)"
    }

    /// 读取分章文件并按顺序拼装全文
    static func assembleText(meta: Meta, directory: URL) -> (String, Int) {
        var parts: [String] = []
        var written = 0
        for (i, ch) in meta.chapters.enumerated() {
            let url = directory
                .appendingPathComponent("chapters", isDirectory: true)
                .appendingPathComponent(String(format: "%05d.txt", i))
            guard let body = try? String(contentsOf: url, encoding: .utf8),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            written += 1
            let heading = normalizedHeading(index: i, title: ch.title)
            parts.append(heading + "\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (parts.joined(separator: "\n\n"), written)
    }

    static func introText(meta: Meta, written: Int) -> String {
        var intro = meta.summary ?? ""
        if let locked = meta.progress.lockedAt {
            intro += (intro.isEmpty ? "" : "\n\n")
            intro += "已缓存前 \(locked) 章(第 \(locked + 1) 章起需在来源站订阅/付费)"
        } else if meta.progress.failed > 0 {
            intro += (intro.isEmpty ? "" : "\n\n")
            intro += "\(meta.progress.failed) 章获取失败,可在书籍详情重新缓存补齐"
        }
        if written < meta.chapters.count && meta.progress.lockedAt == nil && meta.progress.failed == 0 {
            intro += (intro.isEmpty ? "" : "\n\n")
            intro += "已缓存 \(written)/\(meta.chapters.count) 章"
        }
        return intro
    }

    private static func completionNote(meta: Meta, written: Int) -> String {
        if let locked = meta.progress.lockedAt {
            return "已缓存前 \(locked) 章;第 \(locked + 1) 章起需在来源站订阅"
        }
        if meta.progress.failed > 0 {
            return "完成 \(written)/\(meta.chapters.count) 章,\(meta.progress.failed) 章失败,可重新缓存补齐"
        }
        return "全本 \(written) 章已缓存,可离线阅读"
    }

    private static func shelfBook(id: String, context: ModelContext) -> ShelfBook? {
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - 存储

    private func documents() -> URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func cacheRoot() -> URL {
        let dir = documents().appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("chapter-cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func directory(for id: String) -> URL {
        cacheRoot().appendingPathComponent(BookContentStore.safeComponent(id), isDirectory: true)
    }

    private func chaptersDirectory(for id: String) -> URL {
        directory(for: id).appendingPathComponent("chapters", isDirectory: true)
    }

    private func chapterFile(_ id: String, _ index: Int) -> URL {
        chaptersDirectory(for: id).appendingPathComponent(String(format: "%05d.txt", index))
    }

    private func metaURL(_ id: String) -> URL {
        directory(for: id).appendingPathComponent("meta.json")
    }

    private func persist(_ id: String) {
        guard let meta = metas[id] else { return }
        let dir = directory(for: id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: chaptersDirectory(for: id), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL(id), options: .atomic)
        }
    }

    private func loadAll() {
        guard let dirs = try? fm.contentsOfDirectory(at: cacheRoot(), includingPropertiesForKeys: nil) else {
            return
        }
        for dir in dirs {
            let url = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: url),
                  var meta = try? JSONDecoder().decode(Meta.self, from: data) else { continue }
            if meta.progress.state == .queued || meta.progress.state == .downloading {
                meta.progress.state = .paused
                meta.progress.message = "应用曾退出,已暂停,可继续缓存"
            }
            metas[meta.stableID] = meta
            progress[meta.stableID] = meta.progress
        }
    }
}
