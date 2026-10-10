import SwiftData
import XCTest
@testable import NovelFlow

final class DownloadManagerTests: XCTestCase {

    // MARK: - Mock 引擎

    final class MockEngine: DownloadEngineProtocol {
        var fileSize: Int64 = 4096
        var steps: Int = 4
        var stepDelayNanos: UInt64 = 40_000_000
        var failFirst = false
        private(set) var downloadCount = 0

        func download(
            _ request: DownloadRequest,
            progress: @escaping (Int64, Int64) -> Void
        ) async throws -> DownloadOutcome {
            downloadCount += 1
            if failFirst && downloadCount == 1 {
                throw DownloadEngineError.http(500)
            }

            var received: Int64 = 0
            let chunk = max(fileSize / Int64(steps), 1)
            for _ in 0..<steps {
                try await Task.sleep(nanoseconds: stepDelayNanos)
                try Task.checkCancellation()
                received += chunk
                progress(min(received, fileSize), fileSize)
            }

            let fm = FileManager.default
            try? fm.createDirectory(
                at: request.partialFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var content = ""
            for i in 1...60 {
                content += "第\(i)章 下载测试\n\n这是用于下载流程测试的正文内容,长度足够通过导入校验。\n\n"
            }
            try content.write(to: request.partialFileURL, atomically: true, encoding: .utf8)

            return DownloadOutcome(
                partialFileURL: request.partialFileURL,
                receivedBytes: fileSize,
                totalBytes: fileSize,
                etag: "mock-etag",
                serverSupportsRange: true
            )
        }
    }

    // MARK: - 工具

    @MainActor
    private func makeManager(_ engine: MockEngine) -> DownloadManager {
        DownloadManager(engine: engine, storageNamespace: "test-\(UUID().uuidString)")
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ShelfBook.self, ReadingPosition.self, configurations: config)
        return container.mainContext
    }

    private func makeBook(_ id: String = UUID().uuidString) -> SourceBook {
        SourceBook(
            sourceID: "mock",
            sourceBookID: id,
            title: "下载测试-\(id.prefix(6))",
            author: "测试作者",
            cover: nil,
            language: nil,
            summary: "测试摘要",
            subjects: [],
            downloadCount: 0,
            downloadURL: "https://mock.local/\(id).txt",
            downloadFormat: "txt",
            externalURL: nil
        )
    }

    @MainActor
    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("等待条件超时")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - 测试

    @MainActor
    func testDownloadCompletesAndImports() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 30_000_000
        let manager = makeManager(engine)
        let ctx = try makeContext()
        manager.attach(context: ctx)

        let book = makeBook()
        manager.enqueue(book)

        try await waitUntil { manager.task(id: book.id)?.state == .completed }

        let fetched = try ctx.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.sourceID, "mock")
        XCTAssertEqual(manager.task(id: book.id)?.totalBytes, 4096)
        // 完成后的任务移除临时文件(部分下载文件)
        XCTAssertFalse(manager.tasks.contains { $0.state == .downloading })
    }

    @MainActor
    func testPauseThenResume() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 150_000_000
        let manager = makeManager(engine)
        let ctx = try makeContext()
        manager.attach(context: ctx)

        let book = makeBook()
        manager.enqueue(book)
        try await waitUntil { manager.task(id: book.id)?.state == .downloading }

        manager.pause(book.id)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(manager.task(id: book.id)?.state, .paused)

        manager.resume(book.id)
        engine.stepDelayNanos = 30_000_000
        try await waitUntil { manager.task(id: book.id)?.state == .completed }
    }

    @MainActor
    func testCancelCleansUp() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 150_000_000
        let manager = makeManager(engine)
        let ctx = try makeContext()
        manager.attach(context: ctx)

        let book = makeBook()
        manager.enqueue(book)
        try await waitUntil { manager.task(id: book.id)?.state == .downloading }

        manager.cancel(book.id)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(manager.task(id: book.id)?.state, .cancelled)

        // 取消后重试应能重新走完整流程
        engine.stepDelayNanos = 30_000_000
        manager.retry(book.id)
        try await waitUntil { manager.task(id: book.id)?.state == .completed }
    }

    @MainActor
    func testFailureThenRetry() async throws {
        let engine = MockEngine()
        engine.failFirst = true
        engine.stepDelayNanos = 20_000_000
        let manager = makeManager(engine)
        let ctx = try makeContext()
        manager.attach(context: ctx)

        let book = makeBook()
        manager.enqueue(book)
        try await waitUntil { manager.task(id: book.id)?.state == .failed }
        XCTAssertNotNil(manager.task(id: book.id)?.error)

        manager.retry(book.id)
        try await waitUntil { manager.task(id: book.id)?.state == .completed }
    }

    @MainActor
    func testBatchOperations() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 120_000_000
        let manager = makeManager(engine)
        let ctx = try makeContext()
        manager.attach(context: ctx)

        let b1 = makeBook("batch-1")
        let b2 = makeBook("batch-2")
        manager.enqueue(b1)
        manager.enqueue(b2)

        try await waitUntil {
            manager.task(id: b1.id)?.state == .downloading &&
            manager.task(id: b2.id)?.state == .downloading
        }
        manager.pauseAll()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(manager.task(id: b1.id)?.state, .paused)
        XCTAssertEqual(manager.task(id: b2.id)?.state, .paused)

        engine.stepDelayNanos = 30_000_000
        manager.resumeAll()
        try await waitUntil {
            manager.task(id: b1.id)?.state == .completed &&
            manager.task(id: b2.id)?.state == .completed
        }
    }

    @MainActor
    func testReloadMarksUnfinishedAsPaused() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 600_000_000
        let ns = "test-persist-\(UUID().uuidString)"

        let manager1 = DownloadManager(engine: engine, storageNamespace: ns)
        let ctx = try makeContext()
        manager1.attach(context: ctx)
        let book = makeBook()
        manager1.enqueue(book)
        try await waitUntil { manager1.task(id: book.id)?.state == .downloading }

        // 模拟应用重启:同一存储命名空间的新实例
        let manager2 = DownloadManager(engine: MockEngine(), storageNamespace: ns)
        try await waitUntil(3) { manager2.task(id: book.id)?.state == .paused }
        XCTAssertEqual(manager2.task(id: book.id)?.state, .paused)

        manager1.pauseAll()  // 收尾,避免遗留运行中的任务
    }

    @MainActor
    func testDuplicateEnqueueIgnored() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 120_000_000
        let manager = makeManager(engine)
        let ctx = try makeContext()
        manager.attach(context: ctx)

        let book = makeBook()
        manager.enqueue(book)
        try await waitUntil { manager.task(id: book.id)?.state == .downloading }
        manager.enqueue(book)  // 重复点击
        XCTAssertEqual(manager.tasks.filter { $0.id == book.id }.count, 1)
        manager.pauseAll()
    }
}
