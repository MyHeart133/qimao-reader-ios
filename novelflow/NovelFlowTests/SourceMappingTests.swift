import XCTest
@testable import NovelFlow

final class SourceMappingTests: XCTestCase {

    // MARK: - Open Library

    func testOpenLibraryMapping() throws {
        let json = """
        {
          "docs": [
            {
              "key": "/works/OL27448W",
              "title": "The Lord of the Rings",
              "author_name": ["J. R. R. Tolkien", "Co-Author"],
              "first_publish_year": 1954,
              "cover_i": 123456,
              "language": ["eng"],
              "subject": ["Fantasy fiction", "Middle Earth", "Adventure"]
            },
            { "title": "" }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(OLSearchResponse.self, from: Data(json.utf8))
        let books = (decoded.docs ?? []).compactMap(OpenLibrarySource.mapDoc)

        XCTAssertEqual(books.count, 1, "空标题条目应被过滤")
        XCTAssertEqual(books[0].sourceID, "openlibrary")
        XCTAssertEqual(books[0].title, "The Lord of the Rings")
        XCTAssertEqual(books[0].author, "J. R. R. Tolkien; Co-Author")
        XCTAssertEqual(books[0].cover, "https://covers.openlibrary.org/b/id/123456-M.jpg")
        XCTAssertEqual(books[0].externalURL, "https://openlibrary.org/works/OL27448W")
        XCTAssertNil(books[0].downloadURL, "发现型来源不得虚构下载地址")
    }

    func testOpenLibraryMinimalDoc() throws {
        let json = """
        {"docs": [{"title": "Bare Book"}]}
        """
        let decoded = try JSONDecoder().decode(OLSearchResponse.self, from: Data(json.utf8))
        let books = (decoded.docs ?? []).compactMap(OpenLibrarySource.mapDoc)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].author, "")
        XCTAssertNil(books[0].cover)
        XCTAssertNil(books[0].externalURL)
    }

    // MARK: - Webnovel

    func testWebnovelAliasMap() {
        XCTAssertEqual(WebnovelSource.aliasMap["蛊真人"], "Reverend Insanity")
        XCTAssertEqual(WebnovelSource.aliasMap["诡秘之主"], "Lord of the Mysteries")
        XCTAssertEqual(WebnovelSource.aliasMap["斗破苍穹"], "Battle Through the Heavens")
    }

    func testWebnovelSearchLDParsing() {
        let html = """
        <html><head><script type="application/ld+json"> {
          "@context": "https://schema.org",
          "@type": "ItemList",
          "itemListElement": [
            {"@type":"ListItem","position":1,
             "url":"https://www.webnovel.com/book/reverend-insanity_7996858406002505",
             "name":"Reverend Insanity",
             "image":"http://book-pic.webnovel.com/bookcover/7996858406002505?imageMogr2/thumbnail/600",
             "author":{"@type":"Person","name":"Gu Zhen Ren"}},
            {"@type":"ListItem","position":2,
             "url":"https://www.webnovel.com/book/other-book_12345",
             "name":"Other Book",
             "image":"https://book-pic.webnovel.com/bookcover/12345",
             "author":{"@type":"Person","name":"Someone"}}
          ]
        } </script></head><body></body></html>
        """

        let books = WebnovelSource.parseSearchLD(html)
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].sourceBookID, "reverend-insanity_7996858406002505")
        XCTAssertEqual(books[0].title, "Reverend Insanity")
        XCTAssertEqual(books[0].author, "Gu Zhen Ren")
        XCTAssertEqual(books[0].cover?.hasPrefix("https://"), true, "封面 http 必须升级为 https")
        XCTAssertEqual(books[0].externalURL, "https://www.webnovel.com/book/reverend-insanity_7996858406002505")
        XCTAssertNil(books[0].downloadURL)
    }

    func testWebnovelSearchLDNoMatch() {
        let html = "<html><body>no structured data</body></html>"
        XCTAssertTrue(WebnovelSource.parseSearchLD(html).isEmpty)
    }

    func testWebnovelBookPageParsing() {
        let html = """
        <html><head>
        <meta property="og:title" content="Reverend Insanity"/>
        <meta property="og:description" content="The demon is reborn. An old dream in the ancient days."/>
        <meta property="og:image" content="https://book-pic.webnovel.com/bookcover/7996858406002505?imageMogr2/thumbnail/600x"/>
        </head><body></body></html>
        """
        let book = WebnovelSource.parseBookPage(html, bookID: "reverend-insanity_7996858406002505")
        XCTAssertEqual(book.title, "Reverend Insanity")
        XCTAssertTrue(book.summary?.contains("demon") == true)
        XCTAssertEqual(book.cover?.hasPrefix("https://"), true)
        XCTAssertEqual(book.externalURL, "https://www.webnovel.com/book/reverend-insanity_7996858406002505")
    }

    func testWebnovelMetaContentAttributeOrders() {
        let h1 = "<meta property=\"og:title\" content=\"A\"/>"
        let h2 = "<meta content=\"B\" property=\"og:title\"/>"
        XCTAssertEqual(WebnovelSource.metaContent(h1, property: "og:title"), "A")
        XCTAssertEqual(WebnovelSource.metaContent(h2, property: "og:title"), "B")
        XCTAssertNil(WebnovelSource.metaContent("<meta name=\"x\" content=\"y\"/>", property: "og:title"))
    }

    // MARK: - 聚合去重

    private func makeBook(
        source: String, id: String, title: String,
        author: String, download: String? = nil
    ) -> SourceBook {
        SourceBook(
            sourceID: source,
            sourceBookID: id,
            title: title,
            author: author,
            cover: nil,
            language: nil,
            summary: nil,
            subjects: [],
            downloadCount: nil,
            downloadURL: download,
            downloadFormat: download != nil ? "txt" : nil,
            externalURL: nil
        )
    }

    func testDedupePrefersDownloadableVersion() {
        let discoverOnly = makeBook(source: "webnovel", id: "1", title: "Same Book", author: "Same Author")
        let downloadable = makeBook(source: "gutenberg", id: "2", title: "Same Book", author: "Same Author", download: "https://example.com/b.txt")

        let result = SourceRegistry.dedupe([discoverOnly, downloadable])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sourceID, "gutenberg", "同名同作者应保留可下载版本")
        XCTAssertNotNil(result[0].downloadURL)
    }

    func testDedupeKeepsOrderAndDistinctBooks() {
        let a = makeBook(source: "a", id: "1", title: "Book A", author: "X")
        let b = makeBook(source: "b", id: "2", title: "Book B", author: "X")
        let aDup = makeBook(source: "c", id: "3", title: "Book A", author: "X")
        let result = SourceRegistry.dedupe([a, b, aDup])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].title, "Book A")
        XCTAssertEqual(result[1].title, "Book B")
    }

    func testDedupePrefersFirstWhenBothDownloadable() {
        let first = makeBook(source: "gutenberg", id: "1", title: "Nice Book", author: "Z", download: "https://a.txt")
        let second = makeBook(source: "other", id: "2", title: "Nice Book", author: "Z", download: "https://b.txt")
        let result = SourceRegistry.dedupe([first, second])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].downloadURL, "https://a.txt", "同等能力时保留先到者")
    }

    // MARK: - 来源注册表

    func testRegistryContainsAllSources() {
        let ids = Set(SourceRegistry.shared.sources.map { $0.identifier })
        XCTAssertTrue(ids.contains("gutenberg"))
        XCTAssertTrue(ids.contains("openlibrary"))
        XCTAssertTrue(ids.contains("webnovel"))
    }

    func testDiscoverOnlySourcesHaveNoDownloadCapability() {
        guard let webnovel = SourceRegistry.shared.source(withID: "webnovel") else {
            return XCTFail("webnovel 未注册")
        }
        XCTAssertFalse(webnovel.capabilities.fullDownload, "发现型来源不得声明下载能力")
        XCTAssertTrue(webnovel.capabilities.search)

        guard let openlibrary = SourceRegistry.shared.source(withID: "openlibrary") else {
            return XCTFail("openlibrary 未注册")
        }
        XCTAssertFalse(openlibrary.capabilities.fullDownload)

        guard let gutenberg = SourceRegistry.shared.source(withID: "gutenberg") else {
            return XCTFail("gutenberg 未注册")
        }
        XCTAssertTrue(gutenberg.capabilities.fullDownload)
    }
}
