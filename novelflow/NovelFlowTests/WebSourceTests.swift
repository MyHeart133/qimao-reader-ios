import XCTest
@testable import NovelFlow

final class WebSourceTests: XCTestCase {

    // MARK: - 七猫:签名

    func testQimaoQuerySign() {
        let signed = QimaoSource.signedQuery(["a": "1", "b": "2"])
        XCTAssertEqual(signed["sign"], "12eba91ac1503ad62ff49096b82fa411")

        let signed2 = QimaoSource.signedQuery(["page": "1", "wd": "测试", "extend": ""])
        XCTAssertEqual(signed2["sign"], "592a9a794b8230cfb1ac1f4e87232513")
        XCTAssertEqual(signed2["wd"], "测试", "原参数必须保留")
    }

    func testQimaoHeaderSign() {
        let headers = QimaoSource.signedHeaders()
        XCTAssertEqual(headers["sign"], "b90d4260bfa0fd3df36bfdb60bb19631")
        XCTAssertEqual(headers["application-id"], "com.kmxs.reader")
        XCTAssertEqual(headers["User-Agent"], "okhttp/4.9.3")
    }

    // MARK: - 七猫:正文解密

    func testQimaoChapterDecrypt() throws {
        // 用已知密钥/IV 加密的真实格式样本(IV 前 16 字节 + AES-128-CBC/PKCS7)
        let base64 = "AAECAwQFBgcICQoLDA0OD2u6DxxS4H3Cjlb98bGkjtghRpn595uqE2bB4f3RkhO9zl51o63BvT2n09LTTNptt3u9KMMjJ2aZg4NBeQ7xtDs="
        let text = try QimaoSource.decryptChapter(base64)
        XCTAssertEqual(text, "“斗之力，三段！”测试章节内容。")
    }

    func testQimaoChapterDecryptRejectsGarbage() {
        XCTAssertThrowsError(try QimaoSource.decryptChapter("not-base64!!"))
        XCTAssertThrowsError(try QimaoSource.decryptChapter("AAAA"))
    }

    // MARK: - 七猫:映射

    func testQimaoSearchMapping() throws {
        let dict: [String: Any] = [
            "id": "1784900",
            "title": "斗破苍穹",
            "author": "天蚕土豆",
            "intro": "这里是属于斗气的世界",
            "image_link": "https://cdn.wtzw.com/bookimg/f0e5/x.jpg",
            "is_over": "1",
            "ptags": "玄幻,热血",
        ]
        let book = try XCTUnwrap(QimaoSource.mapSearchBook(dict))
        XCTAssertEqual(book.sourceID, "qimao")
        XCTAssertEqual(book.sourceBookID, "1784900")
        XCTAssertEqual(book.title, "斗破苍穹")
        XCTAssertEqual(book.author, "天蚕土豆")
        XCTAssertEqual(book.language, "zh")
        XCTAssertEqual(book.subjects, ["玄幻", "热血"])
        XCTAssertNil(book.downloadURL, "章节目录型来源不得虚构直链")
    }

    func testQimaoSearchMappingFallsBackToOriginalTitle() throws {
        let dict: [String: Any] = ["id": "1", "title": "", "original_title": "原名", "author": ""]
        let book = try XCTUnwrap(QimaoSource.mapSearchBook(dict))
        XCTAssertEqual(book.title, "原名")
    }

    func testQimaoDetailMapping() throws {
        let dict: [String: Any] = [
            "id": "1784900",
            "title": "斗破苍穹",
            "author": "天蚕土豆",
            "intro": "简介",
            "image_link": "https://cdn.wtzw.com/x.jpg",
            "is_over": "1",
            "latest_chapter_title": "大结局",
            "label": "玄幻",
        ]
        let book = QimaoSource.mapDetail(dict)
        XCTAssertTrue(book.subjects.contains("完结"))
        XCTAssertTrue(book.subjects.contains { $0.hasPrefix("最新:") })
    }

    // MARK: - 番茄:字表反混淆

    func testFanqieFontDecodeRoundtrip() {
        // 「此时的燕知春面色沉了下来」的 PUA 混淆形态(来自真实章节页)
        let obfuscated = "\u{E400}\u{E4FC}\u{E4F3}燕\u{E4A4}春\u{E458}\u{E44C}沉\u{E436}\u{E531}\u{E4FA}"
        XCTAssertEqual(FanqieFontMap.decode(obfuscated), "此时的燕知春面色沉了下来")
    }

    func testFanqieFontDecodePassesThrough() {
        XCTAssertEqual(FanqieFontMap.decode("普通文本 without PUA"), "普通文本 without PUA")
        // 未收录的 PUA 原样保留,不破坏其余文本
        XCTAssertEqual(FanqieFontMap.decode("A\u{E999}B"), "A\u{E999}B")
    }

    // MARK: - 番茄:链接解析

    func testFanqieResolveReference() {
        XCTAssertEqual(
            FanqieSource.resolveReference(from: "https://fanqienovel.com/page/7143038691944959011"),
            FanqieReference.book("7143038691944959011")
        )
        XCTAssertEqual(
            FanqieSource.resolveReference(from: "https://fanqienovel.com/reader/7567314951392461374"),
            FanqieReference.chapter("7567314951392461374")
        )
        XCTAssertEqual(
            FanqieSource.resolveReference(from: "7143038691944959011"),
            FanqieReference.book("7143038691944959011")
        )
        XCTAssertNil(FanqieSource.resolveReference(from: "hello"))
        XCTAssertNil(FanqieSource.resolveReference(from: ""))
    }

    // MARK: - 番茄:目录解析

    func testFanqieDirectoryParsing() throws {
        let json: [String: Any] = [
            "data": [
                "allItemIds": ["111", "222"],
                "chapterListWithVolume": [
                    [
                        ["itemId": "111", "title": "第1章 空屋", "needPay": 0, "isChapterLock": false],
                        ["itemId": "222", "title": "第2章 说谎", "needPay": 1, "isChapterLock": true],
                    ]
                ],
            ]
        ]
        let chapters = FanqieSource.parseDirectory(json)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].id, "111")
        XCTAssertEqual(chapters[0].title, "第1章 空屋")
        XCTAssertTrue(chapters[0].isFree)
        XCTAssertFalse(chapters[1].isFree, "付费/锁定章节必须如实标记")
    }

    func testFanqieDirectoryFallbackToItemIDs() {
        let json: [String: Any] = ["data": ["allItemIds": ["a", "b", "c"]]]
        let chapters = FanqieSource.parseDirectory(json)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[1].title, "第2章")
    }

    // MARK: - 番茄:正文

    func testFanqieChapterContentDecodesPUA() throws {
        let html = "<p>\u{E400}\u{E4FC}\u{E4F3}燕\u{E4A4}春\u{E458}\u{E44C}沉\u{E436}\u{E531}\u{E4FA}。</p><p>第二段。</p>"
        let state: [String: Any] = ["reader": ["chapterData": ["content": html, "needPay": 0]]]
        let text = try FanqieSource.chapterContent(fromState: state)
        XCTAssertEqual(text, "此时的燕知春面色沉了下来。\n第二段。")
    }

    func testFanqieChapterContentLocked() {
        let state: [String: Any] = [
            "reader": ["chapterData": ["content": "", "needPay": 1, "isChapterLock": true]]
        ]
        XCTAssertThrowsError(try FanqieSource.chapterContent(fromState: state)) { error in
            guard let sourceError = error as? SourceError, case .unsupported = sourceError else {
                return XCTFail("应抛出 unsupported,实际:\(error)")
            }
        }
    }

    func testFanqieBookPageMapping() throws {
        let page: [String: Any] = [
            "bookId": "7143038691944959011",
            "bookName": "十日终焉",
            "authorName": "杀虫队队员",
            "abstract": "24年番茄年度巅峰榜TOP1",
            "thumbUrl": "https://p9-novel-sign.byteimg.com/x.jpg",
            "status": "1",
            "chapterTotal": 1496,
            "lastChapterTitle": "陈俊南（终）",
        ]
        let book = try XCTUnwrap(FanqieSource.mapBookPage(page, bookID: "7143038691944959011"))
        XCTAssertEqual(book.title, "十日终焉")
        XCTAssertEqual(book.author, "杀虫队队员")
        XCTAssertEqual(book.sourceID, "fanqie")
        XCTAssertEqual(book.externalURL, "https://fanqienovel.com/page/7143038691944959011")
        XCTAssertTrue(book.subjects.contains("共 1496 章"))
        XCTAssertTrue(book.subjects.contains("完结"))
    }

    // MARK: - 起点:搜索解析

    func testQidianSearchParsing() {
        let html = """
        <a class="_bookWrapper_e9qzy_9 _listItem_lrbl7_246 auto-tr" href="//m.qidian.com/chapter/1209977/0/" title="斗破苍穹在线阅读" data-rid="0" data-bid="1209977">
        <div class="_bookImgWrapper_e9qzy_223"><img src="https://imgservices.example.com/placeholder.png" data-src="//bookcover.yuewen.com/qdbimg/349573/1209977/180" alt="斗破苍穹在线阅读"></div>
        <div class="_bookDetailInfo_e9qzy_215"><h2 class="_searchBookName_lrbl7_250"><mark>斗破苍穹</mark></h2>
        <p class="_searchBookDesc_lrbl7_337">这里是属于斗气的世界<mark>斗破苍穹</mark>年番动画</p>
        <div class="_bookTips_e9qzy_161"><p class="_searchBookAuthor_lrbl7_429">天蚕土豆</p>
        <div class="_tags_lrbl7_516"><p>玄幻</p><p>完结</p><p>533.23万字</p></div></div></div></a>
        """
        let books = QidianSource.parseSearch(html)
        XCTAssertEqual(books.count, 1)
        let book = books[0]
        XCTAssertEqual(book.sourceID, "qidian")
        XCTAssertEqual(book.sourceBookID, "1209977")
        XCTAssertEqual(book.title, "斗破苍穹")
        XCTAssertEqual(book.author, "天蚕土豆")
        XCTAssertEqual(book.cover, "https://bookcover.yuewen.com/qdbimg/349573/1209977/180")
        XCTAssertEqual(book.subjects, ["玄幻", "完结", "533.23万字"])
        XCTAssertTrue(book.summary?.contains("斗气的世界") == true)
    }

    // MARK: - 起点:目录解析

    func testQidianCatalogParsing() {
        let html = """
        <a class="_chapterItem_1x6xn_579 auto-tr" href="//m.qidian.com/chapter/1209977/23183869/" title="斗破苍穹 第一章 陨落的天才在线阅读" data-bid="1209977" data-cid="23183869"><div><h2>第一章 陨落的天才</h2></div><span class="_freeText_1x6xn_749"> 免费 </span></a>
        <a class="_chapterItem_1x6xn_579 auto-tr" href="//m.qidian.com/chapter/1209977/28369116/" title="斗破苍穹 第七百五十九章 天雁九行翼在线阅读" data-bid="1209977" data-cid="28369116"><div><h2>第七百五十九章 天雁九行翼</h2></div></a>
        """
        let chapters = QidianSource.parseCatalog(html, bookID: "1209977")
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].id, "23183869")
        XCTAssertEqual(chapters[0].title, "第一章 陨落的天才")
        XCTAssertTrue(chapters[0].isFree)
        XCTAssertFalse(chapters[1].isFree)
    }

    func testQidianCatalogIgnoresOtherBooks() {
        let html = """
        <a class="_chapterItem_1x6xn_579" href="//m.qidian.com/chapter/9999/111/" title="别的书 第一章在线阅读"><div><h2>第一章</h2></div><span> 免费 </span></a>
        """
        XCTAssertTrue(QidianSource.parseCatalog(html, bookID: "1209977").isEmpty)
    }

    // MARK: - 起点:正文与锁定检测

    func testQidianChapterContent() throws {
        let html = """
        <main id="c-23183869" data-type="cjk" class="content mt-1.5em r-font-black"><p> “斗之力，三段！”</p><p> 望着测验魔石碑，少年面无表情。</p></main>
        """
        let text = try QidianSource.chapterContent(fromChapterHTML: html)
        XCTAssertEqual(text, "“斗之力，三段！”\n望着测验魔石碑，少年面无表情。")
    }

    func testQidianLockedChapterThrows() {
        let html = """
        <main id="c-28369116" class="content lock-mask"><p> 第七百五十九章 天雁九行翼</p></main>
        """
        XCTAssertThrowsError(try QidianSource.chapterContent(fromChapterHTML: html)) { error in
            guard let sourceError = error as? SourceError, case .unsupported = sourceError else {
                return XCTFail("VIP 章节应抛出 unsupported,实际:\(error)")
            }
        }
    }

    // MARK: - 缓存:章节标题规范化

    func testNormalizedHeading() {
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 0, title: "第1章 空屋"), "第1章 空屋")
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 1, title: "第一章 陨落的天才"), "第一章 陨落的天才")
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 2, title: "上架感言"), "第3章 上架感言")
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 3, title: ""), "第4章")
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 4, title: "番外 当长大后的萧怀瑾"), "番外 当长大后的萧怀瑾")
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 5, title: "Chapter 5 The End"), "Chapter 5 The End")
        XCTAssertEqual(ChapterCacheManager.normalizedHeading(index: 6, title: "楔子"), "楔子")
    }

    // MARK: - 链接识别

    func testWebLinkResolver() {
        XCTAssertEqual(
            WebLinkResolver.resolve("https://fanqienovel.com/page/7143038691944959011"),
            WebLinkResolver.Resolved.fanqieBook("7143038691944959011")
        )
        XCTAssertEqual(
            WebLinkResolver.resolve("https://fanqienovel.com/reader/7567314951392461374"),
            WebLinkResolver.Resolved.fanqieChapter("7567314951392461374")
        )
        XCTAssertEqual(
            WebLinkResolver.resolve("https://m.qidian.com/book/1209977/"),
            WebLinkResolver.Resolved.qidianBook("1209977")
        )
        XCTAssertEqual(
            WebLinkResolver.resolve("https://m.qidian.com/chapter/1209977/23183869/"),
            WebLinkResolver.Resolved.qidianBook("1209977")
        )
        XCTAssertEqual(WebLinkResolver.resolve("1209977"), WebLinkResolver.Resolved.qidianBook("1209977"))
        XCTAssertEqual(WebLinkResolver.resolve("7567314951392461374"), WebLinkResolver.Resolved.fanqieBook("7567314951392461374"))
        XCTAssertNil(WebLinkResolver.resolve("随便一段文字"))
    }

    // MARK: - 工具

    func testStateExtraction() {
        let html = """
        <html><body><script>window.__INITIAL_STATE__={"page":{"bookName":"十日终焉","chapterTotal":1496}};(function(){})()</script></body></html>
        """
        let state = WebSourceSupport.extractState(from: html)
        let page = WebSourceSupport.dict(state?["page"])
        XCTAssertEqual(WebSourceSupport.string(page?["bookName"]), "十日终焉")
        XCTAssertEqual(WebSourceSupport.int(page?["chapterTotal"]), 1496)
    }

    func testStateExtractionHandlesBracesInStrings() {
        let html = """
        <script>__INITIAL_STATE__={"a":"}not-json{","b":{"c":1}};x</script>
        """
        let state = WebSourceSupport.extractState(from: html)
        XCTAssertEqual(WebSourceSupport.string(state?["a"]), "}not-json{")
        let b = WebSourceSupport.dict(state?["b"])
        XCTAssertEqual(WebSourceSupport.int(b?["c"]), 1)
    }

    func testNormalizedKey() {
        XCTAssertEqual(WebSourceSupport.normalizedKey("《斗破苍穹》"), "斗破苍穹")
        XCTAssertEqual(WebSourceSupport.normalizedKey("斗破 苍穹！"), "斗破苍穹")
        XCTAssertEqual(WebSourceSupport.normalizedKey("A B"), "ab")
    }
}
