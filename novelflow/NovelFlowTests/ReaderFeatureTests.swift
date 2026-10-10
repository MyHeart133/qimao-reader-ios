import SwiftData
import XCTest
@testable import NovelFlow

// MARK: - 全书搜索

final class BookSearchEngineTests: XCTestCase {

    private func makeFixture() -> (text: String, chapters: [StoredChapterMeta], parts: [String]) {
        let parts = [
            "第一章 起点\n\n风从山口吹来,惊起了林子里的鸟。\n他握紧了剑柄。\n",
            "第二章 转折\n\n雨落在青石板上,溅起细小的水花。\n风又起了。\n",
            "第三章 归途\n\n云散开了。\n他回到了家。\n",
        ]
        var text = ""
        var chapters: [StoredChapterMeta] = []
        for (index, part) in parts.enumerated() {
            chapters.append(
                StoredChapterMeta(
                    index: index,
                    title: "第\(index + 1)章",
                    location: (text as NSString).length,
                    length: (part as NSString).length
                )
            )
            text += part
        }
        return (text, chapters, parts)
    }

    func testFindsMatchesWithChapterAndOffset() {
        let (text, chapters, parts) = makeFixture()
        let matches = BookSearchEngine.search(query: "风", fullText: text, chapters: chapters)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].chapterIndex, 0)
        XCTAssertEqual(matches[1].chapterIndex, 1)

        let expectedOffset = (parts[0] as NSString).range(of: "风").location
        XCTAssertEqual(matches[0].chapterOffset, expectedOffset)
        XCTAssertTrue(matches[0].snippet.contains("风"))
    }

    func testSearchIsCaseInsensitive() {
        let text = "第一章\n\nSwift 是一把好剑,swift 又一次出鞘。"
        let chapters = [StoredChapterMeta(index: 0, title: "第一章", location: 0, length: (text as NSString).length)]
        let matches = BookSearchEngine.search(query: "SWIFT", fullText: text, chapters: chapters)
        XCTAssertEqual(matches.count, 2)
    }

    func testSearchRespectsLimit() {
        let text = String(repeating: "灯", count: 30)
        let chapters = [StoredChapterMeta(index: 0, title: "第一章", location: 0, length: (text as NSString).length)]
        let matches = BookSearchEngine.search(query: "灯", fullText: text, chapters: chapters, limit: 7)
        XCTAssertEqual(matches.count, 7)
    }

    func testSearchEmptyOrWhitespaceReturnsEmpty() {
        let (text, chapters, _) = makeFixture()
        XCTAssertTrue(BookSearchEngine.search(query: "", fullText: text, chapters: chapters).isEmpty)
        XCTAssertTrue(BookSearchEngine.search(query: "   ", fullText: text, chapters: chapters).isEmpty)
    }

    func testSearchNoMatchReturnsEmpty() {
        let (text, chapters, _) = makeFixture()
        XCTAssertTrue(BookSearchEngine.search(query: "不存在的词汇", fullText: text, chapters: chapters).isEmpty)
    }

    func testChapterIndexMapping() {
        let (_, chapters, _) = makeFixture()
        XCTAssertEqual(BookSearchEngine.chapterIndex(containing: 0, in: chapters), 0)
        let secondStart = chapters[1].location
        XCTAssertEqual(BookSearchEngine.chapterIndex(containing: secondStart, in: chapters), 1)
        XCTAssertEqual(BookSearchEngine.chapterIndex(containing: secondStart - 1, in: chapters), 0)
        XCTAssertNil(BookSearchEngine.chapterIndex(containing: -5, in: chapters))
    }

    func testExcerptCollapsesWhitespace() {
        let excerpt = BookSearchEngine.excerpt(from: "第一行\n\n  第二行内容", at: 0, maxLength: 20)
        XCTAssertFalse(excerpt.contains("\n"))
        XCTAssertFalse(excerpt.contains("  "))
        XCTAssertTrue(excerpt.hasPrefix("第一行"))
    }

    func testExcerptClampsOffset() {
        XCTAssertEqual(BookSearchEngine.excerpt(from: "短文本", at: 999, maxLength: 8), "本")
    }

    func testExcerptEmptyTextReturnsEmpty() {
        XCTAssertEqual(BookSearchEngine.excerpt(from: "", at: 0), "")
    }
}

// MARK: - 点按分区 / 阅读模式

final class TapZonePresetTests: XCTestCase {

    func testStandardMapping() {
        XCTAssertEqual(TapZonePreset.standard.command(for: 0), .previousPage)
        XCTAssertEqual(TapZonePreset.standard.command(for: 1), .toggleMenu)
        XCTAssertEqual(TapZonePreset.standard.command(for: 2), .nextPage)
    }

    func testLeftHandedSwapsSides() {
        XCTAssertEqual(TapZonePreset.leftHanded.command(for: 0), .nextPage)
        XCTAssertEqual(TapZonePreset.leftHanded.command(for: 2), .previousPage)
    }

    func testWidePresetHasWiderEdges() {
        XCTAssertEqual(TapZonePreset.standard.edgeFraction, 0.28, accuracy: 0.0001)
        XCTAssertGreaterThan(TapZonePreset.wide.edgeFraction, TapZonePreset.standard.edgeFraction)
    }

    func testReadingModeRawValuesRoundTrip() {
        for mode in ReadingMode.allCases {
            XCTAssertEqual(ReadingMode(rawValue: mode.rawValue), mode)
        }
    }
}

// MARK: - 书签存储

@MainActor
final class BookmarkStoreTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Bookmark.self, configurations: config)
    }

    func testInsertFetchDeleteRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let mark = Bookmark(bookID: "b1", chapterIndex: 2, anchorOffset: 120, chapterTitle: "第三章", excerpt: "摘录")
        ctx.insert(mark)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Bookmark>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, "b1#2#120")
        XCTAssertEqual(fetched.first?.chapterTitle, "第三章")
        XCTAssertEqual(fetched.first?.excerpt, "摘录")
        XCTAssertNotNil(fetched.first?.createdAt)

        ctx.delete(mark)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Bookmark>()).count, 0)
    }

    func testUniqueIDComposition() {
        let mark = Bookmark(bookID: "book", chapterIndex: 9, anchorOffset: 456, chapterTitle: "第九章", excerpt: "")
        XCTAssertEqual(mark.id, "book#9#456")
    }
}
