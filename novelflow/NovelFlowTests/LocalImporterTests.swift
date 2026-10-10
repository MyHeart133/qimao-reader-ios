import XCTest
@testable import NovelFlow

final class LocalImporterTests: XCTestCase {

    // MARK: 编码探测

    func testDecodeUTF8Plain() throws {
        let data = Data("你好,世界。Hello!".utf8)
        XCTAssertEqual(try LocalImporter.decodeText(data), "你好,世界。Hello!")
    }

    func testDecodeUTF8WithBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("带 BOM 的文本".utf8))
        XCTAssertEqual(try LocalImporter.decodeText(data), "带 BOM 的文本")
    }

    func testDecodeUTF16WithBOM() throws {
        let data = "UTF-16 中文测试".data(using: .utf16)!
        XCTAssertEqual(try LocalImporter.decodeText(data), "UTF-16 中文测试")
    }

    func testDecodeGB18030() throws {
        // 「中文」的 GBK 字节序列
        let data = Data([0xD6, 0xD0, 0xCE, 0xC4])
        XCTAssertEqual(try LocalImporter.decodeText(data), "中文")
    }

    func testDecodeGB18030Longer() throws {
        // 「第一章 起点」的 GBK 序列
        // 第=0xB5DA 一=0xD2BB 章=0xD5C2 空格=0x20 起=0xC6F0 点=0xB5E3
        let bytes: [UInt8] = [0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2, 0x20, 0xC6, 0xF0, 0xB5, 0xE3]
        XCTAssertEqual(try LocalImporter.decodeText(Data(bytes)), "第一章 起点")
    }

    // MARK: TXT 导入

    func testImportTXTSplitsTitle() throws {
        let text = "第一章 开始\n\n正文一段。\n\n第二章 继续\n\n正文二段。"
        let imported = try LocalImporter.importTXT(data: Data(text.utf8), name: "我的小说.txt")
        XCTAssertEqual(imported.title, "我的小说")
        XCTAssertEqual(imported.format, "txt")
        XCTAssertTrue(imported.text.contains("第一章 开始"))
        XCTAssertTrue(imported.text.contains("第二章 继续"))
    }

    func testImportTXTNormalizesCRLF() throws {
        let raw = "第一章\r\n正文\r\n"
        let imported = try LocalImporter.importTXT(data: Data(raw.utf8), name: "crlf.txt")
        XCTAssertFalse(imported.text.contains("\r"))
        // 章节解析应当识别出章节
        let chapters = ChapterParser.parse(imported.text)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "第一章")
    }

    func testImportTXTEmptyRejected() {
        XCTAssertThrowsError(try LocalImporter.importTXT(data: Data("   \n  ".utf8), name: "empty.txt"))
    }

    // MARK: EPUB 导入

    func testImportEPUBBuildsUnifiedText() throws {
        let data = try XCTUnwrap(
            Data(base64Encoded: TestFixtures.sampleEPUBBase64, options: .ignoreUnknownCharacters),
            "fixture missing"
        )
        let imported = try LocalImporter.importEPUB(data: data, name: "fallback-name.epub")
        XCTAssertEqual(imported.title, "测试小书")
        XCTAssertEqual(imported.author, "测试作者")
        XCTAssertEqual(imported.format, "epub")
        XCTAssertTrue(imported.text.contains("第一章 开始"))
        XCTAssertTrue(imported.text.contains("第二章 继续"))

        // 统一文本经 ChapterParser 应恢复章节结构
        let chapters = ChapterParser.parse(imported.text)
        XCTAssertEqual(chapters.count, 2)
    }

    // MARK: 文件入口

    func testUnsupportedExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.mobi")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try LocalImporter.importFile(at: url))
    }
}
