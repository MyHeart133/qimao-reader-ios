import XCTest
@testable import NovelFlow

/// 下载中心测试:状态机 + 引擎交互(注入 no-op 入库钩子,隔离 SwiftData 与宿主环境)
@MainActor
final class DownloadManagerTests: XCTestCase {

    // MARK: - Mock 引擎

    final class MockEngine: DownloadEngineProtocol {
        var fileSize: Int64 = 4096
        var steps: Int = 4
        var stepDelayNanos: UInt64 = 40_000_000
        var failFirst = false
        var rangeErrorNext = false
        private(set) var downloadCount = 0

        func download(
            _ request: DownloadRequest,
            progress: @escaping (Int64, Int64) -> Void
        ) async throws -> DownloadOutcome {
            downloadCount += 1
            if failFirst && downloadCount == 1 {
                throw DownloadEngineError.http(500)
            }
            if rangeErrorNext {
                rangeErrorNext = false
                throw DownloadEngineError.rangeNotSatisfiable
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
            for i in 1...40 {
                content += "第\(i)章 下载测试\n\n这是用于下载流程测试的正文内容。\n\n"
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

    // MARK: - 夹具

    final class ImportSpy {
        var count = 0
        var lastTitle: String?
        var lastSourceID: String?
    }

    private func makeManager(_ engine: MockEngine) -> (DownloadManager, ImportSpy) {
        let spy = ImportSpy()
        let manager = DownloadManager(
            engine: engine,
            storageNamespace: "test-\(UUID().uuidString)",
            importHandler: { imported, sourceID, _ in
                spy.count += 1
                spy.lastTitle = imported.title
                spy.lastSourceID = sourceID
            }
        )
        return (manager, spy)
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

    /// 轮询等待:每轮主动让出 MainActor 给排队任务执行机会
    private func waitUntil(_ what: String, timeout: TimeInterval = 6, _ condition: () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("等待超时:\(what)")
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - 测试

    func testDownloadCompletesWithImport() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 20_000_000
        let (manager, spy) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("完成") { manager.task(id: book.id)?.state == .completed }

        XCTAssertEqual(manager.task(id: book.id)?.state, .completed)
        XCTAssertEqual(manager.task(id: book.id)?.totalBytes, 4096)
        XCTAssertEqual(spy.count, 1)
        XCTAssertEqual(spy.lastSourceID, "mock")
    }

    func testPauseThenResume() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 80_000_000
        let (manager, spy) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("进入下载") { manager.task(id: book.id)?.state == .downloading }
        XCTAssertEqual(manager.task(id: book.id)?.state, .downloading)

        manager.pause(book.id)
        await waitUntil("暂停落地", timeout: 3) { manager.task(id: book.id)?.state == .paused }
        XCTAssertEqual(manager.task(id: book.id)?.state, .paused)

        engine.stepDelayNanos = 20_000_000
        manager.resume(book.id)
        await waitUntil("恢复后完成") { manager.task(id: book.id)?.state == .completed }
        XCTAssertEqual(spy.count, 1)
    }

    func testCancelThenRetry() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 80_000_000
        let (manager, spy) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("进入下载") { manager.task(id: book.id)?.state == .downloading }

        manager.cancel(book.id)
        await waitUntil("取消落地", timeout: 3) { manager.task(id: book.id)?.state == .cancelled }
        XCTAssertEqual(manager.task(id: book.id)?.state, .cancelled)

        engine.stepDelayNanos = 20_000_000
        manager.retry(book.id)
        await waitUntil("重试后完成") { manager.task(id: book.id)?.state == .completed }
        XCTAssertEqual(spy.count, 1)
    }

    func testFailureThenRetry() async throws {
        let engine = MockEngine()
        engine.failFirst = true
        engine.stepDelayNanos = 20_000_000
        let (manager, _) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("失败落地") { manager.task(id: book.id)?.state == .failed }
        XCTAssertNotNil(manager.task(id: book.id)?.error)

        manager.retry(book.id)
        await waitUntil("重试后完成") { manager.task(id: book.id)?.state == .completed }
    }

    func testBatchPauseAndResume() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 60_000_000
        let (manager, _) = makeManager(engine)
        let b1 = makeBook("batch-1")
        let b2 = makeBook("batch-2")

        manager.enqueue(b1)
        manager.enqueue(b2)
        await waitUntil("两个都进入下载") {
            manager.task(id: b1.id)?.state == .downloading && manager.task(id: b2.id)?.state == .downloading
        }

        manager.pauseAll()
        await waitUntil("批量暂停落地", timeout: 3) {
            manager.task(id: b1.id)?.state == .paused && manager.task(id: b2.id)?.state == .paused
        }
        XCTAssertEqual(manager.activeCount, 0)

        engine.stepDelayNanos = 20_000_000
        manager.resumeAll()
        await waitUntil("批量恢复后完成") {
            manager.task(id: b1.id)?.state == .completed && manager.task(id: b2.id)?.state == .completed
        }
    }

    func testReloadMarksUnfinishedAsPaused() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 600_000_000
        let ns = "test-persist-\(UUID().uuidString)"

        let manager1 = DownloadManager(engine: engine, storageNamespace: ns)
        let book = makeBook()
        manager1.enqueue(book)
        await waitUntil("进入下载") { manager1.task(id: book.id)?.state == .downloading }

        // 模拟应用重启:同存储命名空间的新实例
        let manager2 = DownloadManager(engine: MockEngine(), storageNamespace: ns)
        XCTAssertEqual(manager2.task(id: book.id)?.state, .paused)
        XCTAssertNotNil(manager2.task(id: book.id)?.error)

        manager1.pauseAll()  // 收尾:取消仍在运行的任务
    }

    func testDuplicateEnqueueIgnored() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 80_000_000
        let (manager, _) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("进入下载") { manager.task(id: book.id)?.state == .downloading }
        manager.enqueue(book)
        XCTAssertEqual(manager.tasks.filter { $0.id == book.id }.count, 1)
        manager.pauseAll()
    }

    func testClearFinishedRemovesCompletedRecords() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 20_000_000
        let (manager, _) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("完成") { manager.task(id: book.id)?.state == .completed }
        XCTAssertFalse(manager.tasks.isEmpty)

        manager.clearFinished()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func testRangeNotSatisfiableSelfHeals() async throws {
        let engine = MockEngine()
        engine.stepDelayNanos = 150_000_000
        let (manager, spy) = makeManager(engine)
        let book = makeBook()

        manager.enqueue(book)
        await waitUntil("进入下载") { manager.task(id: book.id)?.state == .downloading }
        await waitUntil("字节上报") { (manager.task(id: book.id)?.receivedBytes ?? 0) > 0 }
        manager.pause(book.id)
        await waitUntil("暂停落地", timeout: 3) { manager.task(id: book.id)?.state == .paused }

        // 恢复时模拟服务端 416:管理器应清掉残档并自动从头续一次,最终完成
        engine.stepDelayNanos = 20_000_000
        engine.rangeErrorNext = true
        manager.resume(book.id)
        await waitUntil("自愈后完成", timeout: 8) { manager.task(id: book.id)?.state == .completed }

        XCTAssertEqual(manager.task(id: book.id)?.state, .completed)
        XCTAssertGreaterThanOrEqual(engine.downloadCount, 3)
        XCTAssertEqual(spy.count, 1)
    }
}
