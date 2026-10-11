import Foundation

/// 全书搜索(纯逻辑,可单测)
enum BookSearchEngine {

    /// 一条命中:章内偏移可直接作为跳转锚点
    struct Match: Identifiable, Equatable {
        let id: String
        let chapterIndex: Int
        let chapterTitle: String
        let chapterOffset: Int
        let snippet: String
    }

    /// 在整本书里检索关键词;大小写不敏感;按出现顺序返回,最多 limit 条
    static func search(
        query: String,
        fullText: String,
        chapters: [StoredChapterMeta],
        limit: Int = 200
    ) -> [Match] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !fullText.isEmpty, !chapters.isEmpty, limit > 0 else { return [] }

        let ns = fullText as NSString
        var matches: [Match] = []
        var searchStart = 0

        while matches.count < limit, searchStart < ns.length {
            let searchRange = NSRange(location: searchStart, length: ns.length - searchStart)
            let found = ns.range(
                of: keyword,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard found.location != NSNotFound, found.length > 0 else { break }

            if let index = chapterIndex(containing: found.location, in: chapters) {
                let chapter = chapters[index]
                let offset = max(0, found.location - chapter.location)
                matches.append(
                    Match(
                        id: "\(index)-\(offset)",
                        chapterIndex: index,
                        chapterTitle: chapter.title,
                        chapterOffset: offset,
                        snippet: snippet(ns: ns, match: found)
                    )
                )
            }

            let next = found.location + max(found.length, 1)
            if next <= searchStart { break }
            searchStart = next
        }
        return matches
    }

    /// 二分查找:位置落在哪个章节(chapters 需按 location 升序)
    static func chapterIndex(containing location: Int, in chapters: [StoredChapterMeta]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var low = 0
        var high = chapters.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if chapters[mid].location <= location {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// 逐章文本检索(在线阅读模式:只搜已缓存的章节)
    /// - Parameter chapters: (chapterIndex, title, text) 列表
    static func search(
        query: String,
        chapters: [(index: Int, title: String, text: String)],
        limit: Int = 200
    ) -> [Match] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, limit > 0 else { return [] }
        var matches: [Match] = []
        for chapter in chapters {
            guard matches.count < limit else { break }
            let ns = chapter.text as NSString
            var searchStart = 0
            while matches.count < limit, searchStart < ns.length {
                let found = ns.range(
                    of: keyword,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: NSRange(location: searchStart, length: ns.length - searchStart)
                )
                guard found.location != NSNotFound, found.length > 0 else { break }
                matches.append(
                    Match(
                        id: "\(chapter.index)-\(found.location)",
                        chapterIndex: chapter.index,
                        chapterTitle: chapter.title,
                        chapterOffset: found.location,
                        snippet: snippet(ns: ns, match: found)
                    )
                )
                let next = found.location + max(found.length, 1)
                if next <= searchStart { break }
                searchStart = next
            }
        }
        return matches
    }

    /// 命中上下文:前后各取一段,折叠空白,首尾按需加省略号
    static func snippet(ns: NSString, match: NSRange, context: Int = 24) -> String {
        let start = max(0, match.location - context)
        let end = min(ns.length, match.location + match.length + context)
        guard end > start else { return "" }
        var text = ns.substring(with: NSRange(location: start, length: end - start))
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "\r", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if start > 0 { text = "…" + text }
        if end < ns.length { text += "…" }
        return text
    }

    /// 书签摘录:从指定位置截取一小段(折叠空白)
    static func excerpt(from text: String, at offset: Int, maxLength: Int = 60) -> String {
        let ns = text as NSString
        guard ns.length > 0 else { return "" }
        let start = max(0, min(offset, ns.length - 1))
        let end = min(ns.length, start + maxLength)
        var snippet = ns.substring(with: NSRange(location: start, length: end - start))
        snippet = snippet.replacingOccurrences(of: "\n", with: " ")
        snippet = snippet.replacingOccurrences(of: "\r", with: " ")
        while snippet.contains("  ") {
            snippet = snippet.replacingOccurrences(of: "  ", with: " ")
        }
        return snippet.trimmingCharacters(in: .whitespaces)
    }
}
