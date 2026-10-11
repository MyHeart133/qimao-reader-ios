import XCTest
@testable import NovelFlow

final class MirrorSourceTests: XCTestCase {

    // MARK: - 202 模板家族

    func testTemplate202SearchParsing() {
        let html = """
        <ul class="txt-list" id="novel-search">
        <li><span class="s2"><a href="/book/598/">蛊真人</a></span><span class="s5">&nbsp;蛊真人</span></li>
        <li><span class="s2"><a href="/book/30872/">蛊真人之邪淫魔尊</a></span><span class="s5">&nbsp;千面兰</span></li>
        </ul>
        """
        let books = Template202Source.parseSearch(html, sourceID: "202xs", base: "https://202xs.com")
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].sourceBookID, "598")
        XCTAssertEqual(books[0].title, "蛊真人")
        XCTAssertEqual(books[0].author, "蛊真人")
        XCTAssertEqual(books[0].sourceID, "202xs")
        XCTAssertEqual(books[0].externalURL, "https://202xs.com/book/598/")
        XCTAssertNil(books[0].downloadURL, "章节型书源不得虚构直链")
    }

    func testTemplate202CatalogPagesAndSort() {
        let html = """
        <select><option value="/book/598/2/">第41-80章</option><option value="/book/598/1/">第1-40章</option></select>
        <ul class="section-list">
        <li><a href="/read/0/598/97942.html"><span class="ico ico-yuedu"></span>立即阅读</a></li>
        <li><a href="/read/0/598/5913241.html">第三百六十八章 方源、巨阳战星宿</a></li>
        <li><a href="/read/0/598/97942.html">第一章 纵身亡魔心仍不悔</a></li>
        <li><a href="/read/0/598/97952.html">第二章 逆光阴五百年觉悟</a></li>
        <li><a href="/read/0/598/5913241.html">第三百六十八章 方源、巨阳战星宿</a></li>
        </ul>
        """
        let pages = Template202Source.catalogPagePaths(from: html, bookID: "598")
        XCTAssertEqual(pages, ["/book/598/1/", "/book/598/2/"])

        let chapters = Template202Source.sortedUnique(
            Template202Source.parseCatalog(html, bookID: "598")
        )
        XCTAssertEqual(chapters.count, 3, "去重且剔除「立即阅读」按钮")
        XCTAssertEqual(chapters[0].id, "97942")
        XCTAssertEqual(chapters[0].title, "第一章 纵身亡魔心仍不悔", "按钮链接不得抢占第一章标题")
        XCTAssertEqual(chapters[2].id, "5913241", "按 ID 数值升序,最新章排最后")
        XCTAssertEqual(chapters[2].index, 3)
    }

    func testTemplate202ChapterPageParsing() throws {
        let html = """
        <h2 class="chapter-title">第一章 纵身亡魔心仍不悔（第1页）</h2>
        <div class="read_btn"><a href="/read/0/598/97942.html">上一章</a><a href="/book/598/">章节目录</a><a href="/read/0/598/97952.html">下一章</a></div>
        <p> 第一段内容。</p><p> 第二段内容。</p>
        <div class="read_btn"><a href="/read/0/598/97942.html">上一章</a></div>
        <div class="phb_fm mt10">推荐</div>
        """
        let page = try XCTUnwrap(Template202Source.parseChapterPage(html))
        XCTAssertEqual(page.pageNumber, 1)
        XCTAssertEqual(page.text, "第一段内容。\n第二段内容。")
        XCTAssertTrue(page.title.contains("第一章"))
    }

    func testTemplate202ChapterPageFiltersAds() throws {
        let html = """
        <h2 class="chapter-title">第2页</h2>
        <div class="read_btn">nav</div>
        <p> 正文一。</p><p>一秒记住【笔趣阁】biquge365.net，更新快，无弹窗！</p><p> 正文二。</p>
        <div class="read_btn">nav2</div>
        """
        let page = try XCTUnwrap(Template202Source.parseChapterPage(html))
        XCTAssertEqual(page.pageNumber, 2)
        XCTAssertFalse(page.text.contains("一秒记住"))
        XCTAssertTrue(page.text.contains("正文一。"))
        XCTAssertTrue(page.text.contains("正文二。"))
    }

    // MARK: - 飘天文学

    func testPiaotiaGBKEncoding() {
        XCTAssertEqual(WebSourceSupport.percentEncodedGBK("蛊真人"), "%B9%C6%D5%E6%C8%CB")
        let bytes = Data([0xB9, 0xC6, 0xD5, 0xE6, 0xC8, 0xCB])
        XCTAssertEqual(WebSourceSupport.decode(bytes, encoding: .gb18030), "蛊真人")
    }

    func testPiaotiaSearchParsing() {
        let html = """
        <table>
        <tr>
        <td class="odd"><a href="https://www.piaotia.com/bookinfo/3/3355.html">蛊真人</a></td>
        <td class="even"><a href="https://www.piaotia.com/html/3/3355/index.html" target="_blank"> 第三百六十八节：方源、巨阳战星宿</a></td>
        <td class="odd">蛊真人</td>
        <td class="even">20226K</td>
        <td class="odd" align="center">19-05-30</td>
        <td class="even" align="center">全本</td>
        </tr>
        </table>
        """
        let books = PiaotiaSource.parseSearch(html)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].sourceBookID, "3/3355")
        XCTAssertEqual(books[0].title, "蛊真人")
        XCTAssertEqual(books[0].author, "蛊真人")
        XCTAssertEqual(books[0].subjects, ["全本"])
        XCTAssertEqual(books[0].externalURL, "https://www.piaotia.com/bookinfo/3/3355.html")
    }

    func testPiaotiaCatalogParsing() {
        let html = """
        <a href="1710628.html">第一节：纵身亡魔心仍不悔</a>
        <a href="1710629.html">第二节：逆光阴五百年觉悟</a>
        <a href="1710629.html">第二节：逆光阴五百年觉悟</a>
        <a href="/help/index.html">帮助</a>
        """
        let chapters = PiaotiaSource.parseCatalog(html)
        XCTAssertEqual(chapters.count, 2, "去重且只保留章节链接")
        XCTAssertEqual(chapters[0].id, "1710628")
        XCTAssertEqual(chapters[1].index, 2)
    }

    func testPiaotiaChapterParsing() {
        let html = """
        <H1><a href="https://www.piaotia.com/bookinfo/3/3355.html">蛊真人</a> 第一卷：魔性不改 第一节：纵身亡魔心仍不悔</H1>
        <div class="toplink"><a href="index.html">上一章</a></div>
        <br> &nbsp;&nbsp;“方源，乖乖地交出春秋蝉，我给你个痛快！”<br /> <br />
        &nbsp;&nbsp;第二段文字。<br /> <br />
        &nbsp;&nbsp;{飘天文学<a href="https://www.piaotia.com" target="_blank">www.piaotia.com</a>感谢各位书友的支持，您的支持就是我们最大的动力} </div>
        <div class="bottomlink"><A href="index.html">上一章</a></div>
        """
        let text = PiaotiaSource.parseChapter(html)
        XCTAssertTrue(text.contains("“方源，乖乖地交出春秋蝉，我给你个痛快！”"))
        XCTAssertTrue(text.contains("第二段文字。"))
        XCTAssertFalse(text.contains("飘天文学"), "站点广告行必须过滤")
        XCTAssertFalse(text.contains("上一章"))
    }

    // MARK: - 笔趣阁 365

    func testBiquge365SearchParsing() {
        let html = """
        <li><span class="lei"><a href="/sort/3_1/">[都市言情]</a></span><span class="name"><a href="/book/479771/" title="蛊真人之以画求神文章列表">蛊真人之以画求神</a></span><span class="jie"><a href="/chapter/479771/02978998.html">30.历史总是惊人的相似。</a></span><span class="zuo"><a href="/author/天羽空翼">天羽空翼</a></span><span class="time">05-07</span></li>
        """
        let books = Biquge365Source.parseSearch(html)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].sourceBookID, "479771")
        XCTAssertEqual(books[0].title, "蛊真人之以画求神")
        XCTAssertEqual(books[0].author, "天羽空翼")
        XCTAssertEqual(books[0].externalURL, "https://www.biquge365.net/book/479771/")
    }

    func testBiquge365CatalogKeepsDOMOrder() {
        let html = """
        <h2>《蛊真人之以画求神》全部章节</h2>
        <ul class="info">
        <li><a href="/chapter/479771/88878998.html" title="1.成？败？">1.成？败？</a></li>
        <li><a href="/chapter/479771/98878998.html" title="2.布局五域（上）">2.布局五域（上）</a></li>
        <li><a href="/chapter/479771/88878998.html">1.成？败？</a></li>
        </ul>
        """
        let chapters = Biquge365Source.parseCatalog(html, bookID: "479771")
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].id, "88878998", "必须保持 DOM 顺序(不按 ID 数值排序)")
        XCTAssertEqual(chapters[1].id, "98878998")
    }

    func testBiquge365ChapterParsing() {
        let html = """
        <div id="txt" class="txt">
        <p style="font-weight:bold";>一秒记住【笔趣阁】biquge365.net，更新快，无弹窗！</p><br>
        &nbsp;&nbsp;第一段文字。<br/>&nbsp;&nbsp;第二段文字。<br/>
        </div>
        <div class="other">其他</div>
        """
        let text = Biquge365Source.parseChapter(html)
        XCTAssertEqual(text, "第一段文字。\n第二段文字。")
    }

    func testBiquge365ChapterMissingContainer() {
        XCTAssertEqual(Biquge365Source.parseChapter("<html><body>无正文</body></html>"), "")
    }

    // MARK: - 注册表

    func testRegistryContainsMirrors() {
        let ids = Set(SourceRegistry.shared.sources.map(\.identifier))
        for expected in ["qimao", "fanqie", "qidian", "202xs", "ffzw", "xinbiqu", "piaotia", "biquge365"] {
            XCTAssertTrue(ids.contains(expected), "缺少书源:\(expected)")
        }
    }
}
