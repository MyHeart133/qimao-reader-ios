import Foundation

/// 解析出的章节
struct ParsedChapter: Identifiable, Equatable {
    let id: Int
    let index: Int
    let title: String
    /// 在源文本中的 UTF-16 范围(含标题行本身)
    let range: NSRange
}

/// TXT 章节解析器
///
/// 原则:
/// - 只做无损规范化(CRLF → LF、去 BOM),不删除作者保留的空白与标点
/// - 逐行匹配标题(行首锚定 + 行长限制),降低正文误报
/// - 无任何标题时返回单章「全文」,绝不丢字
enum ChapterParser {

    // MARK: 规范化

    static func normalize(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("\u{FEFF}") {
            s.removeFirst()
        }
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        return s
    }

    // MARK: 标题规则(保守集)

    private static let regexes: [NSRegularExpression] = {
        let patterns = [
            // 第X章 + 可选空格 + 可选标题(章类:无空格也允许,最常见)
            "^第[0-9零一二三四五六七八九十百千万两]+章[ 　]?[^\\n]{0,30}$",
            // 第X节/回/卷/集/部/篇(要求标题前有空格,避免"第三节课"这类正文误报)
            "^第[0-9零一二三四五六七八九十百千万两]+[节回卷集部篇][ 　]+[^\\n]{0,30}$",
            // 卷/篇前置式:卷X / 番外 / 序章 等
            "^(?:卷|篇)[0-9零一二三四五六七八九十百千万两]{1,12}[ 　]*[^\\n]{0,30}$",
            "^(?:序章|序言|楔子|引子|尾声|后记|番外|终章)[^\\n]{0,20}$",
            // 英文章节
            "^(?:Chapter|CHAPTER|chapter)[ 　]+[0-9IVXLCDMivxlcdm]{1,10}[^\\n]{0,60}$",
        ]
        return patterns.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
    }()

    private static func isChapterTitle(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 50 else { return false }
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)
        for rx in regexes {
            if rx.firstMatch(in: trimmed, range: full) != nil {
                return true
            }
        }
        return false
    }

    // MARK: 解析

    /// 解析文本为章节列表。输入应为 `normalize(_:)` 处理后的文本;
    /// 若直接传入原始文本,内部会先规范化(注意:此时 range 以规范化文本为准)。
    static func parse(_ text: String) -> [ParsedChapter] {
        let ns = text as NSString
        guard ns.length > 0 else {
            return [ParsedChapter(id: 0, index: 0, title: "全文", range: NSRange(location: 0, length: 0))]
        }

        var marks: [(offset: Int, title: String)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { sub, subRange, _, _ in
            guard let line = sub else { return }
            if isChapterTitle(line) {
                marks.append((subRange.location, line.trimmingCharacters(in: .whitespaces)))
            }
        }

        guard !marks.isEmpty else {
            return [ParsedChapter(id: 0, index: 0, title: "全文", range: NSRange(location: 0, length: ns.length))]
        }

        var chapters: [ParsedChapter] = []

        // 第一个标题之前的内容 → 「前言」章(不丢字)
        if marks[0].offset > 0 {
            let prefixRange = NSRange(location: 0, length: marks[0].offset)
            let prefix = ns.substring(with: prefixRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                chapters.append(ParsedChapter(id: 0, index: 0, title: "前言", range: prefixRange))
            }
        }

        for (i, mark) in marks.enumerated() {
            let start = mark.offset
            let end = i + 1 < marks.count ? marks[i + 1].offset : ns.length
            chapters.append(ParsedChapter(
                id: chapters.count,
                index: chapters.count,
                title: mark.title,
                range: NSRange(location: start, length: end - start)
            ))
        }
        return chapters
    }

    /// 便捷:规范化 + 解析
    static func parseNormalized(_ raw: String) -> (text: String, chapters: [ParsedChapter]) {
        let text = normalize(raw)
        return (text, parse(text))
    }
}
