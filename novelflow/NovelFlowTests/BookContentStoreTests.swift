import SwiftData
import XCTest
@testable import NovelFlow

final class BookContentStoreTests: XCTestCase {

    func testSaveLoadDeleteRoundTrip() throws {
        let store = BookContentStore.shared
        let bookID = "test-\(UUID().uuidString)"
        defer { try? store.delete(bookID: bookID) }

        let text = "第一章 起点\n\n正文内容甲。\n\n第二章 终点\n\n正文内容乙。"
        let rel = try store.save(text: text, bookID: bookID)
        XCTAssertTrue(rel.contains("content.txt"))
        XCTAssertTrue(store.exists(bookID: bookID))

        let loaded = try store.loadText(bookID: bookID)
        XCTAssertEqual(loaded, text)

        let chapters = try store.loadChapters(bookID: bookID)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第一章 起点")
        XCTAssertEqual(chapters[1].title, "第二章 终点")

        try store.delete(bookID: bookID)
        XCTAssertFalse(store.exists(bookID: bookID))
    }

    func testChapterOffsetsAreValid() throws {
        let store = BookContentStore.shared
        let bookID = "test-\(UUID().uuidString)"
        defer { try? store.delete(bookID: bookID) }

        let text = "前言部分。\n第一章 甲\n甲正文。\n第二章 乙\n乙正文。"
        try store.save(text: text, bookID: bookID)
        let chapters = try store.loadChapters(bookID: bookID)
        let ns = text as NSString
        for ch in chapters {
            XCTAssertGreaterThanOrEqual(ch.location, 0)
            XCTAssertLessThanOrEqual(ch.location + ch.length, ns.length)
        }
    }
}

@MainActor
final class LibraryFlowTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ShelfBook.self, ReadingPosition.self, configurations: config)
    }

    func testAddImportedCreatesShelfEntryAndFiles() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let imported = ImportedBook(
            id: UUID().uuidString,
            title: "导入测试书",
            author: "某作者",
            text: "第一章 甲\n\n内容甲。\n第二章 乙\n\n内容乙。",
            format: "txt",
            originalFileName: "test.txt"
        )
        let book = try LibraryService.addImported(imported, sourceID: "local-import", context: ctx)
        defer { LibraryService.deleteCompletely(book, context: ctx) }

        XCTAssertTrue(BookContentStore.shared.exists(bookID: book.id))
        let text = try BookContentStore.shared.loadText(bookID: book.id)
        XCTAssertTrue(text.contains("第一章"))

        let fetched = try ctx.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.sourceID, "local-import")
    }

    func testRemoveFromShelfKeepsFiles() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let imported = ImportedBook(
            id: UUID().uuidString, title: "保留测试", author: "",
            text: "第一章\n内容。", format: "txt", originalFileName: "k.txt"
        )
        let book = try LibraryService.addImported(imported, sourceID: "local-import", context: ctx)
        let bookID = book.id
        defer { try? BookContentStore.shared.delete(bookID: bookID) }

        LibraryService.removeFromShelf(book, context: ctx)
        XCTAssertFalse(BookContentStore.shared.exists(bookID: bookID) == false,
                       "移出书架不应删除文件")
        XCTAssertTrue(BookContentStore.shared.exists(bookID: bookID))
    }

    func testDeleteCompletelyRemovesFilesAndProgress() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let imported = ImportedBook(
            id: UUID().uuidString, title: "删除测试", author: "",
            text: "第一章\n内容。", format: "txt", originalFileName: "d.txt"
        )
        let book = try LibraryService.addImported(imported, sourceID: "local-import", context: ctx)
        let bookID = book.id

        ctx.insert(ReadingPosition(bookID: bookID, chapterIndex: 0, anchorOffset: 3, percentage: 0.1))
        try? ctx.save()

        LibraryService.deleteCompletely(book, context: ctx)

        XCTAssertFalse(BookContentStore.shared.exists(bookID: bookID))
        let positions = try ctx.fetch(FetchDescriptor<ReadingPosition>())
        XCTAssertTrue(positions.isEmpty, "进度应随书删除")
        let books = try ctx.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertTrue(books.isEmpty)
    }
}
