import XCTest
import SwiftData
@testable import NovelFlow

final class ModelsTests: XCTestCase {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ShelfBook.self, ReadingPosition.self,
            configurations: config
        )
    }

    @MainActor
    func testInsertAndFetchShelfBook() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let book = ShelfBook(id: "local-1", title: "测试书", author: "某作者", sourceID: "local-import")
        ctx.insert(book)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "测试书")
        XCTAssertEqual(fetched.first?.sourceID, "local-import")
        XCTAssertNotNil(fetched.first?.addedAt)
    }

    @MainActor
    func testReadingPositionRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let pos = ReadingPosition(bookID: "b1", chapterIndex: 3, anchorOffset: 1200, percentage: 0.42)
        ctx.insert(pos)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ReadingPosition>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.chapterIndex, 3)
        XCTAssertEqual(fetched.first?.anchorOffset, 1200)
        XCTAssertEqual(fetched.first?.percentage ?? 0, 0.42, accuracy: 0.0001)
    }

    @MainActor
    func testDeleteBookKeepsDatabaseConsistent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(ShelfBook(id: "a", title: "甲", sourceID: "local-import"))
        ctx.insert(ShelfBook(id: "b", title: "乙", sourceID: "local-import"))
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertEqual(all.count, 2)

        if let target = all.first(where: { $0.id == "a" }) {
            ctx.delete(target)
        }
        try ctx.save()

        let rest = try ctx.fetch(FetchDescriptor<ShelfBook>())
        XCTAssertEqual(rest.count, 1)
        XCTAssertEqual(rest.first?.id, "b")
    }
}
