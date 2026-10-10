import Foundation

struct EPUBChapter: Equatable {
    var title: String
    var text: String
}

struct EPUBBook: Equatable {
    var title: String
    var author: String
    var chapters: [EPUBChapter]
}

enum EPUBError: LocalizedError {
    case invalidArchive
    case missingContainer
    case missingOPF
    case emptySpine

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "EPUB 文件无效(不是有效的 ZIP 容器)"
        case .missingContainer: return "EPUB 缺少 container.xml"
        case .missingOPF: return "EPUB 缺少 OPF 文档"
        case .emptySpine: return "EPUB 没有可读章节"
        }
    }
}

/// EPUB 2/3 解析器(核心子集)
///
/// 处理:container.xml → OPF(metadata/manifest/spine)→ XHTML 正文提取
/// 安全:不执行任何脚本;script/style 内容一律剔除
/// 边界:损坏 ZIP / 缺失文件 → 明确报错,不产出半成品
enum EPUBParser {

    static func parse(data: Data) throws -> EPUBBook {
        let zip: MiniZipReader
        do {
            zip = try MiniZipReader(data: data)
        } catch {
            throw EPUBError.invalidArchive
        }

        // 1) container.xml → OPF 路径
        guard let containerData = zip.read("META-INF/container.xml"),
              let containerXML = String(data: containerData, encoding: .utf8),
              let opfPath = firstCapture(pattern: "full-path\\s*=\\s*\"([^\"]+)\"", in: containerXML) else {
            throw EPUBError.missingContainer
        }

        // 2) OPF
        guard let opfData = zip.read(opfPath),
              let opfXML = String(data: opfData, encoding: .utf8) else {
            throw EPUBError.missingOPF
        }
        let opf = parseOPF(opfXML)
        guard !opf.spine.isEmpty else { throw EPUBError.emptySpine }

        // 3) 按 spine 顺序提取章节文本
        let baseDir = (opfPath as NSString).deletingLastPathComponent
        var chapters: [EPUBChapter] = []
        for (i, idref) in opf.spine.enumerated() {
            guard let href = opf.manifest[idref] else { continue }
            let path = joinPath(baseDir, href)
            var chapterData = zip.read(path)
            if chapterData == nil, let decoded = path.removingPercentEncoding {
                chapterData = zip.read(decoded)
            }
            guard let d = chapterData else { continue }
            let html = String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
            let text = extractText(from: html)
            if text.isEmpty { continue }
            let title = extractHeading(from: html) ?? "章节 \(i + 1)"
            chapters.append(EPUBChapter(title: title, text: text))
        }

        guard !chapters.isEmpty else { throw EPUBError.emptySpine }
        return EPUBBook(title: opf.title, author: opf.author, chapters: chapters)
    }

    // MARK: - OPF

    struct OPFData {
        var title = ""
        var author = ""
        var manifest: [String: String] = [:]   // id → href
        var spine: [String] = []               // idrefs(按顺序)
    }

    static func parseOPF(_ xml: String) -> OPFData {
        let delegate = OPFDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.result
    }

    private final class OPFDelegate: NSObject, XMLParserDelegate {
        var result = OPFData()
        private var buffer = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            buffer = ""
            let name = elementName.lowercased()
            if name.hasSuffix("item") || name == "item" {
                if let id = attributeDict["id"], let href = attributeDict["href"] {
                    result.manifest[id] = href
                }
            } else if name.hasSuffix("itemref") || name == "itemref" {
                if let idref = attributeDict["idref"] {
                    result.spine.append(idref)
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = elementName.lowercased()
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasSuffix("title"), result.title.isEmpty, !trimmed.isEmpty {
                result.title = trimmed
            } else if name.hasSuffix("creator"), result.author.isEmpty, !trimmed.isEmpty {
                result.author = trimmed
            }
            buffer = ""
        }
    }

    // MARK: - XHTML → 文本

    static func extractText(from html: String) -> String {
        var s = html
        // 剔除脚本与样式内容
        s = s.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?is)<head[^>]*>.*?</head>", with: " ", options: .regularExpression)

        // 只保留 body(存在时)
        if let bodyRange = s.range(of: "(?is)<body[^>]*>(.*?)</body>", options: .regularExpression) {
            s = String(s[bodyRange])
        }
        s = s.replacingOccurrences(of: "(?is)</?body[^>]*>", with: "\n", options: .regularExpression)

        // 块级元素 → 换行
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(
            of: "(?i)</(p|div|h1|h2|h3|h4|h5|h6|li|tr|blockquote|section|article|figure)[^>]*>",
            with: "\n",
            options: .regularExpression
        )

        // 去除其余标签
        s = s.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)

        // 实体解码
        s = decodeEntities(s)

        // 行规整:行尾去空白、连续空行折叠为一个
        var lines: [String] = []
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if lines.isEmpty || lines.last?.isEmpty == true { continue }
                lines.append("")
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractHeading(from html: String) -> String? {
        for tag in ["h1", "h2", "h3", "title"] {
            if let captured = firstCapture(pattern: "(?is)<\(tag)[^>]*>(.*?)</\(tag)>", in: html) {
                let text = decodeEntities(captured.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && text.count <= 60 {
                    return text
                }
            }
        }
        return nil
    }

    // MARK: - 工具

    static func decodeEntities(_ input: String) -> String {
        var s = input
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}"), ("&middot;", "\u{00B7}"),
        ]
        for (k, v) in named {
            s = s.replacingOccurrences(of: k, with: v)
        }
        // 数字实体 &#123; / &#x1F600;
        if let rx = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = s as NSString
            let matches = rx.matches(in: s, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let isHex = ns.substring(with: m.range(at: 1)) == "x"
                let digits = ns.substring(with: m.range(at: 2))
                guard let value = UInt32(digits, radix: isHex ? 16 : 10),
                      let scalar = Unicode.Scalar(value),
                      let range = Range(m.range, in: s) else { continue }
                s.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return s
    }

    static func firstCapture(pattern: String, in text: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func joinPath(_ base: String, _ relative: String) -> String {
        if base.isEmpty { return relative }
        if relative.hasPrefix("/") {
            return String(relative.dropFirst())
        }
        return base + "/" + relative
    }
}
