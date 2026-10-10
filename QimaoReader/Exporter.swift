import Foundation

/// TXT / EPUB 导出
enum Exporter {
    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|\r\n\t")
        let t = s.components(separatedBy: bad).joined(separator: "·")
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "book" : String(trimmed.prefix(100))
    }

    /// 输出目录:App 沙盒 Documents/qimao(文件 App 可见)
    static func outputDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("qimao", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: TXT

    static func saveTXT(book: QBook, chapters: [(String, String)]) -> URL? {
        var buf = "《\(book.title)》\n"
        var meta: [String] = []
        if !book.author.isEmpty { meta.append("作者:\(book.author)") }
        if book.isOver { meta.append("状态:完结") }
        if !meta.isEmpty { buf += meta.joined(separator: " | ") + "\n" }
        if !book.intro.isEmpty {
            buf += "\n【简介】\n\(book.intro)\n"
        }
        buf += "\n" + String(repeating: "=", count: 30) + "\n"
        for (t, c) in chapters {
            buf += "\n\(t)\n\n\(c)\n"
        }
        let url = outputDir().appendingPathComponent("\(safeName(book.title)).txt")
        do {
            try buf.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: EPUB

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func saveEPUB(book: QBook, chapters: [(String, String)], cover: Data?) -> URL? {
        var zip = ZipWriter()
        zip.add("mimetype", text: "application/epub+zip")
        zip.add("META-INF/container.xml", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """)
        zip.add("OEBPS/style.css", text: "body{font-family:serif;line-height:1.8;margin:1em;}h2{font-size:1.2em;}p{text-indent:2em;margin:.6em 0;}")

        var manifest = ""
        var spine = ""
        for i in chapters.indices {
            let id = "c\(i + 1)"
            manifest += "<item id=\"\(id)\" href=\"c\(pad(i + 1)).xhtml\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"\(id)\"/>"
        }
        var coverManifest = ""
        var coverSpine = ""
        if cover != nil {
            coverManifest = "<item id=\"cimg\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/><item id=\"cpage\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
            coverSpine = "<itemref idref=\"cpage\"/>"
        }

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="uid">urn:uuid:\(UUID().uuidString)</dc:identifier>
        <dc:title>\(esc(book.title))</dc:title>
        <dc:creator>\(esc(book.author))</dc:creator>
        <dc:language>zh-CN</dc:language>
        </metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="style.css" media-type="text/css"/>\(coverManifest)\(manifest)</manifest>
        <spine>\(coverSpine)<itemref idref="nav"/>\(spine)</spine>
        </package>
        """
        zip.add("OEBPS/content.opf", text: opf)

        var navItems = ""
        for (i, ch) in chapters.enumerated() {
            navItems += "<li><a href=\"c\(pad(i + 1)).xhtml\">\(esc(ch.0))</a></li>"
        }
        zip.add("OEBPS/nav.xhtml", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>目录</title></head>
        <body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><h1>目录</h1><ol>\(navItems)</ol></nav></body></html>
        """)

        if let coverData = cover {
            zip.add("OEBPS/cover.jpg", coverData)
            zip.add("OEBPS/cover.xhtml", text: """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>封面</title></head>
            <body style="margin:0;text-align:center"><img src="cover.jpg" style="max-width:100%"/></body></html>
            """)
        }

        for (i, ch) in chapters.enumerated() {
            var paras = ""
            for line in ch.1.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty {
                    paras += "<p>\(esc(t))</p>"
                }
            }
            zip.add("OEBPS/c\(pad(i + 1)).xhtml", text: """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(esc(ch.0))</title><link rel="stylesheet" href="style.css"/></head>
            <body><h2>\(esc(ch.0))</h2>\(paras)</body></html>
            """)
        }

        let url = outputDir().appendingPathComponent("\(safeName(book.title)).epub")
        do {
            try zip.finalize().write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func pad(_ n: Int) -> String {
        String(format: "%04d", n)
    }

    // MARK: 封面下载

    static func fetchCover(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data.count > 1000 ? data : nil
        } catch {
            return nil
        }
    }
}
