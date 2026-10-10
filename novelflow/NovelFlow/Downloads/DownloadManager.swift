import Foundation
import SwiftData
import SwiftUI

/// 下载管理:任务队列 + 状态机 + 持久化
///
/// 职责边界:
/// - 网络传输 → DownloadEngine(可注入,便于测试)
/// - 解析与入库 → LocalImporter + LibraryService
/// - 本类:状态流转 / 队列调度 / 暂停恢复 / 取消重试 / 批量操作 / 持久化
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    /// 入库钩子:默认走 LibraryService(落盘 + SwiftData);测试可注入 no-op 以隔离环境
    typealias DownloadImportHandler = (ImportedBook, String, String?) async throws -> Void

    @Published private(set) var tasks: [DownloadTask] = []

    private let engine: DownloadEngineProtocol
    private let storageNamespace: String
    private let importHandler: DownloadImportHandler?
    private var runners: [String: Task<Void, Never>] = [:]
    private var speedMarks: [String: (date: Date, bytes: Int64)] = [:]
    private var context: ModelContext?

    init(
        engine: DownloadEngineProtocol = URLSessionDownloadEngine(),
        storageNamespace: String = "default",
        importHandler: DownloadImportHandler? = nil
    ) {
        self.engine = engine
        self.storageNamespace = storageNamespace
        self.importHandler = importHandler
        loadPersisted()
        // 重启语义:不假设任务可自动恢复;未完成任务标记为暂停
        var changed = false
        for i in tasks.indices where tasks[i].state == .queued || tasks[i].state == .downloading {
            tasks[i].state = .paused
            tasks[i].error = "应用曾退出,任务已暂停,可点击恢复"
            tasks[i].updatedAt = Date()
            changed = true
        }
        if changed { persist() }
    }

    /// App 启动时注入 SwiftData 上下文
    func attach(context: ModelContext) {
        self.context = context
    }

    // MARK: - 查询

    var activeCount: Int {
        tasks.filter { $0.state.isActive }.count
    }

    var unfinishedCount: Int {
        tasks.filter { !$0.state.isFinished || $0.state == .failed }.count
    }

    func filtered(_ filter: DownloadFilter) -> [DownloadTask] {
        tasks.filter { filter.matches($0) }
    }

    func task(id: String) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    // MARK: - 入口操作

    /// 入队(已存在活跃任务时忽略;已完成时忽略;失败/暂停/取消时重试)
    func enqueue(_ book: SourceBook) {
        if let existing = task(id: book.id) {
            switch existing.state {
            case .completed, .queued, .downloading:
                return
            case .failed, .cancelled, .paused:
                retry(existing.id)
                return
            }
        }
        guard var newTask = DownloadTask.from(book) else {
            if let i = tasks.firstIndex(where: { $0.id == book.id }) {
                tasks[i].state = .failed
                tasks[i].error = "该来源未提供下载地址"
                persist()
            }
            return
        }
        newTask.state = .queued
        tasks.insert(newTask, at: 0)
        persist()
        start(id: newTask.id)
    }

    // MARK: - 单任务操作

    func pause(_ id: String) {
        guard let i = index(of: id) else { return }
        guard tasks[i].state == .downloading || tasks[i].state == .queued else { return }
        runners[id]?.cancel()
        runners[id] = nil
        tasks[i].state = .paused
        tasks[i].speedBytesPerSec = 0
        tasks[i].updatedAt = Date()
        persist()
    }

    func resume(_ id: String) {
        guard let i = index(of: id), tasks[i].state == .paused else { return }
        start(id: id)
    }

    func cancel(_ id: String) {
        guard let i = index(of: id) else { return }
        runners[id]?.cancel()
        runners[id] = nil
        tasks[i].state = .cancelled
        tasks[i].speedBytesPerSec = 0
        tasks[i].error = nil
        tasks[i].updatedAt = Date()
        removePartial(id)
        persist()
    }

    func retry(_ id: String) {
        guard let i = index(of: id) else { return }
        runners[id]?.cancel()
        runners[id] = nil
        removePartial(id)
        tasks[i].receivedBytes = 0
        tasks[i].totalBytes = -1
        tasks[i].etag = nil
        tasks[i].error = nil
        tasks[i].speedBytesPerSec = 0
        tasks[i].state = .queued
        tasks[i].updatedAt = Date()
        persist()
        start(id: id)
    }

    /// 移除任务记录(仅限已结束状态)
    func remove(_ id: String) {
        guard let i = index(of: id), tasks[i].state.isFinished else { return }
        removePartial(id)
        tasks.remove(at: i)
        persist()
    }

    // MARK: - 批量操作

    func pauseAll() {
        for t in tasks where t.state.isActive {
            pause(t.id)
        }
    }

    func resumeAll() {
        for t in tasks where t.state == .paused {
            resume(t.id)
        }
    }

    func cancelAll() {
        for t in tasks where t.state.isActive || t.state == .paused {
            cancel(t.id)
        }
    }

    func clearCompleted() {
        tasks.removeAll { $0.state == .completed }
        persist()
    }

    func clearFinished() {
        for t in tasks where t.state.isFinished {
            removePartial(t.id)
        }
        tasks.removeAll { $0.state.isFinished }
        persist()
    }

    /// 部分下载文件占用(字节)
    func partialTotalSize() -> Int64 {
        let dir = partialDirectory()
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - 调度

    private func start(id: String) {
        guard runners[id] == nil else { return }
        guard let i = index(of: id), let url = URL(string: tasks[i].url) else {
            if let j = index(of: id) {
                tasks[j].state = .failed
                tasks[j].error = "下载地址无效"
                persist()
            }
            return
        }
        tasks[i].state = .downloading
        tasks[i].error = nil
        tasks[i].updatedAt = Date()
        speedMarks[id] = (Date(), tasks[i].receivedBytes)
        persist()

        let partial = partialFileURL(for: id)
        let runner = Task { [weak self] in
            guard let self else { return }
            await self.runTransfer(id: id, url: url, partial: partial)
        }
        runners[id] = runner
    }

    private func runTransfer(id: String, url: URL, partial: URL) async {
        defer { runners[id] = nil }
        guard let i = index(of: id) else { return }
        let request = DownloadRequest(
            url: url,
            partialFileURL: partial,
            resumeFrom: tasks[i].receivedBytes,
            expectedETag: tasks[i].etag
        )

        do {
            let outcome = try await engine.download(request) { received, total in
                Task { @MainActor [weak self] in
                    self?.updateProgress(id: id, received: received, total: total)
                }
            }
            if Task.isCancelled { return }
            await finishDownload(id: id, outcome: outcome)
        } catch is CancellationError {
            // 暂停/取消已由对应操作更新状态;此处仅收尾
        } catch {
            if let j = index(of: id), tasks[j].state == .downloading {
                tasks[j].state = .failed
                tasks[j].speedBytesPerSec = 0
                tasks[j].error = error.localizedDescription
                tasks[j].updatedAt = Date()
                persist()
            }
        }
    }

    private func updateProgress(id: String, received: Int64, total: Int64) {
        guard let i = index(of: id), tasks[i].state == .downloading else { return }
        let now = Date()
        if let mark = speedMarks[id] {
            let dt = now.timeIntervalSince(mark.date)
            if dt >= 0.8 {
                let dBytes = received - mark.bytes
                tasks[i].speedBytesPerSec = dt > 0 ? Double(dBytes) / dt : 0
                speedMarks[id] = (now, received)
            }
        } else {
            speedMarks[id] = (now, received)
        }
        tasks[i].receivedBytes = received
        if total > 0 {
            tasks[i].totalBytes = total
        }
    }

    // MARK: - 完成与校验

    private func finishDownload(id: String, outcome: DownloadOutcome) async {
        guard let i = index(of: id) else { return }

        // 1) 传输完整性:已知总长时必须一致
        if outcome.totalBytes > 0 && outcome.receivedBytes < outcome.totalBytes {
            tasks[i].state = .failed
            tasks[i].error = "文件不完整(\(outcome.receivedBytes)/\(outcome.totalBytes) 字节)"
            tasks[i].updatedAt = Date()
            persist()
            return
        }

        // 2) 读取 + 解析(后台)
        let data: Data
        do {
            data = try Data(contentsOf: outcome.partialFileURL)
        } catch {
            tasks[i].state = .failed
            tasks[i].error = "无法读取下载文件"
            persist()
            return
        }
        guard data.count >= 32 else {
            tasks[i].state = .failed
            tasks[i].error = "文件内容异常(过小)"
            persist()
            return
        }

        let format = tasks[i].format
        let title = tasks[i].title
        let sourceID = tasks[i].sourceID
        let summary = tasks[i].summary

        do {
            if let handler = importHandler {
                // 测试/自定义路径:跳过重型解析与 SwiftData,直接交付字节级校验结果
                let quick = ImportedBook(
                    id: UUID().uuidString,
                    title: title,
                    author: "",
                    text: "payload:\(data.count)",
                    format: format,
                    originalFileName: title + "." + format
                )
                try await handler(quick, sourceID, summary)
            } else {
                // 生产路径:后台解析 → 落盘 → SwiftData 入库
                let parsed: ImportedBook = try await Task.detached(priority: .userInitiated) {
                    if format == "epub" {
                        return try LocalImporter.importEPUB(data: data, name: title + ".epub")
                    } else {
                        return try LocalImporter.importTXT(data: data, name: title + ".txt")
                    }
                }.value

                var merged = parsed
                if merged.title.isEmpty || merged.title.count < 2 {
                    merged.title = title
                }
                guard let ctx = context else {
                    throw ImportError.decodeFailed
                }
                let book = try LibraryService.addImported(merged, sourceID: sourceID, context: ctx)
                book.intro = summary ?? ""
                book.contentSignature = "bytes:\(outcome.receivedBytes)"
                try? ctx.save()
            }

            // 4) 更新任务
            if let j = index(of: id) {
                tasks[j].state = .completed
                tasks[j].receivedBytes = outcome.receivedBytes
                tasks[j].totalBytes = max(outcome.totalBytes, outcome.receivedBytes)
                tasks[j].etag = outcome.etag
                tasks[j].error = nil
                tasks[j].speedBytesPerSec = 0
                tasks[j].updatedAt = Date()
            }
            persist()
            removePartial(id)   // 内容已转存,清理下载临时文件
        } catch {
            if let j = index(of: id) {
                tasks[j].state = .failed
                tasks[j].error = "校验/入库失败：\(error.localizedDescription)"
                tasks[j].updatedAt = Date()
            }
            persist()
        }
    }

    // MARK: - 存储

    private func index(of id: String) -> Int? {
        tasks.firstIndex { $0.id == id }
    }

    private func downloadsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func partialDirectory() -> URL {
        let dir = downloadsDirectory().appendingPathComponent("partial", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func partialFileURL(for id: String) -> URL {
        partialDirectory().appendingPathComponent(BookContentStore.safeComponent(id) + ".part")
    }

    private func removePartial(_ id: String) {
        try? FileManager.default.removeItem(at: partialFileURL(for: id))
    }

    private func tasksFileURL() -> URL {
        downloadsDirectory().appendingPathComponent("tasks-\(storageNamespace).json")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: tasksFileURL(), options: .atomic)
    }

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: tasksFileURL()),
              let list = try? JSONDecoder().decode([DownloadTask].self, from: data) else { return }
        tasks = list
    }
}
