import SwiftData
import XCTest
@testable import NovelFlow

final class OnlineReadingTests: XCTestCase {

    // MARK: - 在线章节存储

    func testOnlineChapterStoreRoundtrip() throws {
        let bookID = "test-online-\(UUID().uuidString)"
        defer { OnlineChapterStore.shared.deleteAll(bookID: bookID) }

        let meta = OnlineBookMeta(
            sourceID: "202xs",
            sourceBookID: "598",
            title: "蛊真人",
            author: "蛊真人",
            chapters: [
                OnlineChapterRef(id: "97942", title: "第一章 纵身亡魔心仍不悔"),
                OnlineChapterRef(id: "97952", title: "第二章 逆光阴五百年觉悟"),
            ],
            updatedAt: Date()
        )
        try OnlineChapterStore.shared.saveMeta(meta, bookID: bookID)

        let loaded = try XCTUnwrap(OnlineChapterStore.shared.meta(bookID: bookID))
        XCTAssertEqual(loaded.sourceID, "202xs")
        XCTAssertEqual(loaded.sourceBookID, "598")
        XCTAssertEqual(loaded.chapterCount, 2)
        XCTAssertEqual(loaded.chapters[0].title, "第一章 纵身亡魔心仍不悔")

        XCTAssertNil(OnlineChapterStore.shared.chapterText(bookID: bookID, index: 0))
        OnlineChapterStore.shared.saveChapter(bookID: bookID, index: 0, text: "第一段。\n第二段。")
        XCTAssertEqual(OnlineChapterStore.shared.chapterText(bookID: bookID, index: 0), "第一段。\n第二段。")
        XCTAssertEqual(OnlineChapterStore.shared.cachedChapterCount(bookID: bookID), 1)
    }

    // MARK: - 在线书架(不下载全文即可入架)

    @MainActor
    func testEnsureOnlineShelfBookCreatesAndReuses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = SourceBook(
            sourceID: "202xs",
            sourceBookID: "598",
            title: "蛊真人",
            author: "蛊真人",
            cover: nil,
            language: "zh",
            summary: "简介",
            subjects: [],
            downloadCount: nil,
            downloadURL: nil,
            downloadFormat: nil,
            externalURL: nil
        )
        let meta = OnlineBookMeta(
            sourceID: "202xs",
            sourceBookID: "598",
            title: "蛊真人",
            author: "蛊真人",
            chapters: [OnlineChapterRef(id: "1", title: "第一章")],
            updatedAt: Date()
        )
        defer { OnlineChapterStore.shared.deleteAll(bookID: book.stableID) }

        let shelf = try LibraryService.ensureOnlineShelfBook(book: book, meta: meta, context: context)
        XCTAssertEqual(shelf.id, "202xs:598", "在线书架 ID 必须是 stableID(与整本缓存升级共用)")
        XCTAssertTrue(shelf.isOnline)
        XCTAssertNil(shelf.localPath)
        XCTAssertEqual(shelf.sourceBookID, "598")
        XCTAssertTrue(OnlineChapterStore.shared.hasMeta(bookID: shelf.id), "目录必须已落盘")

        // 二次调用不重复建档
        let again = try LibraryService.ensureOnlineShelfBook(book: book, meta: meta, context: context)
        XCTAssertEqual(again.id, shelf.id)
        let all = try context.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertEqual(all.count, 1)
    }

    func testIsOnlineFlag() {
        let online = ShelfBook(id: "a", title: "x", sourceID: "202xs", sourceBookID: "1", localPath: nil)
        XCTAssertTrue(online.isOnline)

        let cached = ShelfBook(id: "b", title: "x", sourceID: "202xs", sourceBookID: "1",
                               localPath: "Books/b/content.txt")
        XCTAssertFalse(cached.isOnline, "整本缓存后(有 localPath)不再是纯在线书")

        let imported = ShelfBook(id: "c", title: "x", sourceID: "local-import",
                                 localPath: "Books/c/content.txt")
        XCTAssertFalse(imported.isOnline)
    }

    // MARK: - 逐章文本搜索(在线阅读模式)

    func testSearchAcrossChapterTexts() {
        let chapters: [(index: Int, title: String, text: String)] = [
            (0, "第一章", "风从山口吹来。"),
            (1, "第二章", "风又起了。"),
            (2, "第三章", "云散开了。"),
        ]
        let matches = BookSearchEngine.search(query: "风", chapters: chapters)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].chapterIndex, 0)
        XCTAssertEqual(matches[1].chapterIndex, 1)
        XCTAssertEqual(matches[0].chapterOffset, 0)
        XCTAssertTrue(matches[0].snippet.contains("风"))
    }

    func testSearchAcrossChapterTextsRespectsLimitAndEmptyQuery() {
        let chapters: [(index: Int, title: String, text: String)] = [
            (0, "第一章", String(repeating: "灯", count: 10)),
        ]
        XCTAssertTrue(BookSearchEngine.search(query: "  ", chapters: chapters).isEmpty)
        XCTAssertEqual(BookSearchEngine.search(query: "灯", chapters: chapters, limit: 4).count, 4)
    }

    // MARK: - 搜索超时包装

    func testWithTimeoutReturnsFastResult() async throws {
        let value = try await SourceRegistry.withTimeout(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testWithTimeoutThrowsOnSlowOperation() async {
        do {
            _ = try await SourceRegistry.withTimeout(seconds: 0.2) {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return 1
            }
            XCTFail("应当超时")
        } catch {
            // 预期:超时抛错
        }
    }

    // MARK: - 工具

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ShelfBook.self, ReadingPosition.self, Bookmark.self,
            configurations: config
        )
    }
}
