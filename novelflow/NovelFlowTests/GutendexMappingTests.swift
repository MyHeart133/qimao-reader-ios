import XCTest
@testable import NovelFlow

final class GutendexMappingTests: XCTestCase {

    private let fullJSON = """
    {
      "id": 1342,
      "title": "Pride and Prejudice",
      "authors": [{"name": "Austen, Jane", "birth_year": 1775, "death_year": 1817}],
      "summaries": ["A classic novel of manners."],
      "subjects": ["Love stories", "England -- Fiction"],
      "languages": ["en"],
      "formats": {
        "text/html": "https://example.com/1342.html",
        "application/epub+zip": "https://example.com/1342.epub",
        "text/plain; charset=utf-8": "https://example.com/1342.txt",
        "image/jpeg": "https://example.com/cover.jpg"
      },
      "download_count": 99999
    }
    """

    func testFullMapping() throws {
        let book = try JSONDecoder().decode(GutendexBook.self, from: Data(fullJSON.utf8))
        let mapped = GutendexSource.mapBook(book)

        XCTAssertEqual(mapped.sourceID, "gutenberg")
        XCTAssertEqual(mapped.sourceBookID, "1342")
        XCTAssertEqual(mapped.title, "Pride and Prejudice")
        XCTAssertEqual(mapped.author, "Austen, Jane")
        XCTAssertEqual(mapped.downloadFormat, "txt", "优先取 UTF-8 纯文本")
        XCTAssertEqual(mapped.downloadURL, "https://example.com/1342.txt")
        XCTAssertEqual(mapped.cover, "https://example.com/cover.jpg")
        XCTAssertEqual(mapped.language, "en")
        XCTAssertEqual(mapped.downloadCount, 99999)
        XCTAssertEqual(mapped.summary, "A classic novel of manners.")
        XCTAssertEqual(mapped.subjects.count, 2)
        XCTAssertTrue(mapped.externalURL?.contains("1342") == true)
    }

    func testPrefersEPUBWhenNoTextFormats() throws {
        let json = """
        {"id": 5, "title": "T", "formats": {"application/epub+zip": "https://example.com/5.epub"}, "download_count": 1}
        """
        let book = try JSONDecoder().decode(GutendexBook.self, from: Data(json.utf8))
        let mapped = GutendexSource.mapBook(book)
        XCTAssertEqual(mapped.downloadFormat, "epub")
        XCTAssertEqual(mapped.downloadURL, "https://example.com/5.epub")
    }

    func testNoDownloadableFormat() throws {
        let json = """
        {"id": 6, "title": "T2", "formats": {"text/html": "https://example.com/6.html"}}
        """
        let book = try JSONDecoder().decode(GutendexBook.self, from: Data(json.utf8))
        let mapped = GutendexSource.mapBook(book)
        XCTAssertNil(mapped.downloadURL, "无 txt/epub 时不得虚构下载地址")
        XCTAssertNil(mapped.downloadFormat)
    }

    func testMissingOptionalFields() throws {
        let json = """
        {"id": 7, "title": "Minimal", "formats": {"text/plain; charset=us-ascii": "https://example.com/7.txt"}}
        """
        let book = try JSONDecoder().decode(GutendexBook.self, from: Data(json.utf8))
        let mapped = GutendexSource.mapBook(book)
        XCTAssertEqual(mapped.author, "")
        XCTAssertNil(mapped.cover)
        XCTAssertNil(mapped.language)
        XCTAssertEqual(mapped.downloadFormat, "txt")
        XCTAssertEqual(mapped.downloadURL, "https://example.com/7.txt")
    }

    func testListResponseDecoding() throws {
        let json = """
        {"count": 2, "results": [
            {"id": 1, "title": "A", "formats": {}},
            {"id": 2, "title": "B", "formats": {}}
        ]}
        """
        let list = try JSONDecoder().decode(GutendexListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.results?.count, 2)
    }
}
