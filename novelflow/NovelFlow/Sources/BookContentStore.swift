import Foundation

/// 章节元数据(缓存于 chapters.json;location/length 为 UTF-16 偏移)
struct StoredChapterMeta: Codable, Equatable {
    var index: Int
    var title: String
    var location: Int
    var length: Int
}

/// 书籍内容文件存储
///
/// 目录结构:
///   Documents/Books/{bookID}/content.txt     规范化全文
///   Documents/Books/{bookID}/chapters.json   章节缓存(解析结果)
///
/// 说明:本类型为纯同步文件操作,调用方负责放置到后台任务。
final class BookContentStore {
    static let shared = BookContentStore()

    private let fm = FileManager.default

    func booksRoot() -> URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Books", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func directory(for bookID: String) -> URL {
        booksRoot().appendingPathComponent(Self.safeComponent(bookID), isDirectory: true)
    }

    static func safeComponent(_ id: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = id.components(separatedBy: bad).joined(separator: "_")
        return cleaned.isEmpty ? "book" : cleaned
    }

    /// 保存全文并生成章节缓存;返回相对路径(存进 ShelfBook.localPath)
    @discardableResult
    func save(text: String, bookID: String) throws -> String {
        let dir = directory(for: bookID)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let textURL = dir.appendingPathComponent("content.txt")
        try text.write(to: textURL, atomically: true, encoding: .utf8)

        let parsed = ChapterParser.parse(text)
        let metas = parsed.map {
            StoredChapterMeta(index: $0.index, title: $0.title, location: $0.range.location, length: $0.range.length)
        }
        let metaURL = dir.appendingPathComponent("chapters.json")
        try JSONEncoder().encode(metas).write(to: metaURL, options: .atomic)

        return "Books/\(Self.safeComponent(bookID))/content.txt"
    }

    func loadText(bookID: String) throws -> String {
        let url = directory(for: bookID).appendingPathComponent("content.txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func loadChapters(bookID: String) throws -> [StoredChapterMeta] {
        let url = directory(for: bookID).appendingPathComponent("chapters.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([StoredChapterMeta].self, from: data)
    }

    func exists(bookID: String) -> Bool {
        let url = directory(for: bookID).appendingPathComponent("content.txt")
        return fm.fileExists(atPath: url.path)
    }

    /// 删除某本书的全部本地内容
    func delete(bookID: String) throws {
        let dir = directory(for: bookID)
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    /// 全部本地书籍内容占用(字节)
    func totalSize() -> Int64 {
        let root = booksRoot()
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
