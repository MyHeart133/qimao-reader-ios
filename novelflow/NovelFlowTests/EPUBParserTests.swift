import XCTest
@testable import NovelFlow

final class EPUBParserTests: XCTestCase {

    private func sampleData() throws -> Data {
        guard let data = Data(base64Encoded: TestFixtures.sampleEPUBBase64, options: .ignoreUnknownCharacters) else {
            throw XCTSkip("EPUB fixture 缺失")
        }
        return data
    }

    func testZipReaderFindsEntries() throws {
        let zip = try MiniZipReader(data: try sampleData())
        XCTAssertTrue(zip.contains("mimetype"))
        XCTAssertTrue(zip.contains("META-INF/container.xml"))
        XCTAssertTrue(zip.contains("OEBPS/content.opf"))
        XCTAssertTrue(zip.contains("OEBPS/c1.xhtml"))
    }

    func testStoreMethodReadsRaw() throws {
        // mimetype 以 STORE 方式存储
        let zip = try MiniZipReader(data: try sampleData())
        let raw = try XCTUnwrap(zip.read("mimetype"))
        XCTAssertEqual(String(decoding: raw, as: UTF8.self), "application/epub+zip")
    }

    func testDeflateMethodInflates() throws {
        // c1.xhtml 以 DEFLATE 存储
        let zip = try MiniZipReader(data: try sampleData())
        let raw = try XCTUnwrap(zip.read("OEBPS/c1.xhtml"))
        let html = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(html.contains("第一章"))
    }

    func testParseMetadata() throws {
        let book = try EPUBParser.parse(data: try sampleData())
        XCTAssertEqual(book.title, "测试小书")
        XCTAssertEqual(book.author, "测试作者")
    }

    func testChaptersInSpineOrder() throws {
        let book = try EPUBParser.parse(data: try sampleData())
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertTrue(book.chapters[0].title.contains("第一章"))
        XCTAssertTrue(book.chapters[0].text.contains("这是第一章的正文"))
        XCTAssertTrue(book.chapters[1].title.contains("第二章"))
        XCTAssertTrue(book.chapters[1].text.contains("带实体"))
    }

    func testScriptContentRemoved() throws {
        let book = try EPUBParser.parse(data: try sampleData())
        for chapter in book.chapters {
            XCTAssertFalse(chapter.text.contains("evil"))
            XCTAssertFalse(chapter.text.contains("var "))
        }
    }

    func testEntityDecoding() {
        let html = "<p>A&nbsp;B &amp; C &#65; &#x42; D</p>"
        let text = EPUBParser.extractText(from: html)
        XCTAssertEqual(text, "A B & C A B D")
    }

    func testBlockElementsBecomeNewlines() {
        let html = "<div><p>第一段</p><p>第二段</p></div>"
        let text = EPUBParser.extractText(from: html)
        XCTAssertEqual(text, "第一段\n第二段")
    }

    func testInvalidDataRejected() {
        let junk = Data("this is not a zip archive at all".utf8)
        XCTAssertThrowsError(try EPUBParser.parse(data: junk))
    }

    func testEmptyZipRejected() throws {
        // 空 Data 不是合法 zip
        XCTAssertThrowsError(try MiniZipReader(data: Data()))
    }
}
