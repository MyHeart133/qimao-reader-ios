import XCTest
@testable import NovelFlow

final class PaginationTests: XCTestCase {

    private func makeText(_ targetLength: Int = 3000) -> String {
        var s = ""
        var i = 0
        while (s as NSString).length < targetLength {
            s += "段落\(i)。他走进雨里,街灯把水洼照得发亮——像无数个小小的月亮。\"你来了。\"她说,声音轻得像叹气。The rain kept falling, softly, gently, endlessly.\n\n"
            i += 1
        }
        return s
    }

    func testNoCharacterLostOrDuplicated() {
        let text = makeText()
        let result = PaginationEngine.paginate(
            text: text,
            typography: ReaderTypography(),
            pageSize: CGSize(width: 300, height: 500)
        )
        XCTAssertFalse(result.pages.isEmpty)
        var expected = 0
        for p in result.pages {
            XCTAssertEqual(p.location, expected, "页范围不连续")
            XCTAssertGreaterThan(p.length, 0)
            expected += p.length
        }
        XCTAssertEqual(expected, result.sourceLength)
        XCTAssertEqual(result.sourceLength, (text as NSString).length, "分页覆盖必须等于全文长度")
    }

    func testAnchorRecoveryAcrossFontSizeChange() {
        let text = makeText()
        let size = CGSize(width: 320, height: 560)
        var typo = ReaderTypography()
        typo.fontSize = 16
        let small = PaginationEngine.paginate(text: text, typography: typo, pageSize: size)
        XCTAssertGreaterThan(small.pages.count, 3)

        // 使用第 3 页的起始位置作为锚点
        let anchor = small.pages[2].location
        typo.fontSize = 24
        let large = PaginationEngine.paginate(text: text, typography: typo, pageSize: size)

        guard let idx = PaginationEngine.pageIndex(containing: anchor, in: large) else {
            return XCTFail("锚点未找到对应页")
        }
        let p = large.pages[idx]
        XCTAssertTrue(p.location <= anchor && anchor < p.location + p.length, "锚点应落在该页范围内")
    }

    func testAnchorRecoveryAcrossMarginChange() {
        let text = makeText()
        var typo = ReaderTypography()
        let sizeA = CGSize(width: 340, height: 600)
        let a = PaginationEngine.paginate(text: text, typography: typo, pageSize: sizeA)
        let anchor = a.pages[min(4, a.pages.count - 1)].location

        typo.horizontalMargin = 34
        let sizeB = CGSize(width: 340 - (typo.horizontalMargin - ReaderTypography().horizontalMargin) * 2, height: 600)
        let b = PaginationEngine.paginate(text: text, typography: typo, pageSize: sizeB)
        XCTAssertNotNil(PaginationEngine.pageIndex(containing: anchor, in: b))
    }

    func testEmptyTextYieldsNoPages() {
        let r = PaginationEngine.paginate(
            text: "",
            typography: ReaderTypography(),
            pageSize: CGSize(width: 300, height: 500)
        )
        XCTAssertTrue(r.pages.isEmpty)
        XCTAssertEqual(r.sourceLength, 0)
    }

    func testExtremelySmallPageTerminates() {
        let text = makeText(400)
        let r = PaginationEngine.paginate(
            text: text,
            typography: ReaderTypography(),
            pageSize: CGSize(width: 24, height: 24)
        )
        XCTAssertLessThan(r.pages.count, 100_000)
        for p in r.pages {
            XCTAssertGreaterThan(p.length, 0)
        }
    }

    func testNarrowColumnFullCoverage() {
        let text = makeText(1200)
        let r = PaginationEngine.paginate(
            text: text,
            typography: ReaderTypography(),
            pageSize: CGSize(width: 140, height: 260)
        )
        let total = r.pages.reduce(0) { $0 + $1.length }
        XCTAssertEqual(total, (text as NSString).length)
    }

    func testPageIndexClampsOutOfRangeAnchor() {
        let text = makeText(600)
        let r = PaginationEngine.paginate(
            text: text,
            typography: ReaderTypography(),
            pageSize: CGSize(width: 300, height: 400)
        )
        XCTAssertNotNil(PaginationEngine.pageIndex(containing: -5, in: r))
        XCTAssertNotNil(PaginationEngine.pageIndex(containing: 999_999, in: r))
    }

    func testProgressMonotonic() {
        let text = makeText(2000)
        let r = PaginationEngine.paginate(
            text: text,
            typography: ReaderTypography(),
            pageSize: CGSize(width: 320, height: 480)
        )
        var last = -1.0
        for i in 0..<r.pages.count {
            let p = PaginationEngine.progress(ofPage: i, in: r)
            XCTAssertGreaterThanOrEqual(p, last)
            last = p
        }
        XCTAssertEqual(PaginationEngine.progress(ofPage: r.pages.count - 1, in: r), last, accuracy: 0.0001)
    }
}
