import XCTest
@testable import NovelFlow

final class ChapterParserTests: XCTestCase {

    func testChineseChapterTitles() {
        let text = "第一章 启程\n正文甲。\n第二章 相遇\n正文乙。\n第三章\n正文丙。"
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "第一章 启程")
        XCTAssertEqual(chapters[1].title, "第二章 相遇")
        XCTAssertEqual(chapters[2].title, "第三章")
        XCTAssertEqual(chapters[0].range.location, 0)
        XCTAssertEqual(chapters[2].range.location + chapters[2].range.length, (text as NSString).length)
    }

    func testChineseNumeralsAndOtherUnits() {
        let text = "第一百二十三章 大结局\n正文。\n第五节 风起\n又一段。\n卷三\n卷正文。"
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertTrue(chapters[0].title.contains("第一百二十三章"))
        XCTAssertTrue(chapters[1].title.contains("第五节"))
        XCTAssertTrue(chapters[2].title.contains("卷三"))
    }

    func testEnglishChapter() {
        let text = "Chapter 1 The Beginning\nText here.\nCHAPTER XII\nThe end."
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertTrue(chapters[0].title.contains("Chapter 1"))
    }

    func testNoChapterReturnsWholeText() {
        let text = "就是一段没有章节标记的文字。\n第二段。"
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "全文")
        XCTAssertEqual(chapters[0].range.length, (text as NSString).length)
    }

    func testPrefixBecomesIntroChapter() {
        let text = "这是前景文字。\n第一章 开始\n正文。"
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "前言")
    }

    func testFalsePositiveGuardian() {
        // 正文句子中的"第三节课"不应被识别为章节标题
        let text = "他翻开了第三节课的课本,皱起眉头。\n第一章 真章节\n正文。"
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "前言")
        XCTAssertEqual(chapters[1].title, "第一章 真章节")
    }

    func testNormalizeCRLFAndBOM() {
        let raw = "\u{FEFF}第一章\r\n正文\r\n"
        let out = ChapterParser.normalize(raw)
        XCTAssertFalse(out.hasPrefix("\u{FEFF}"))
        XCTAssertFalse(out.contains("\r"))
        XCTAssertTrue(out.contains("\n"))
    }

    func testEmptyText() {
        let chapters = ChapterParser.parse("")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].range.length, 0)
    }

    func testChapterRangesAreContiguous() {
        let text = "前言啊。\n第一章 甲\n内容甲\n第二章 乙\n内容乙\n第三章 丙\n内容丙"
        let chapters = ChapterParser.parse(text)
        XCTAssertGreaterThanOrEqual(chapters.count, 3)
        for i in 0..<(chapters.count - 1) {
            XCTAssertEqual(
                chapters[i].range.location + chapters[i].range.length,
                chapters[i + 1].range.location,
                "chapter \(i) 与 \(i + 1) 之间出现缝隙或重叠"
            )
        }
    }

    func testSpecialHeadings() {
        let text = "序章\n开端。\n正文段落。\n尾声\n结局。"
        let chapters = ChapterParser.parse(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "序章")
        XCTAssertEqual(chapters[1].title, "尾声")
    }
}
