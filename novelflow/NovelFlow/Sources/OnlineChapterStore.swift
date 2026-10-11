import Foundation

/// 在线书籍的章节缓存(边读边存)
///
/// 目录结构:
///   Documents/Books/{bookID}/online/meta.json     章节目录 + 来源信息
///   Documents/Books/{bookID}/online/{idx:05d}.txt 已读章节正文
///
/// 与 BookContentStore 共用同一本书目录:整本缓存完成后 content.txt 落盘,
/// 阅读器自动切回本地全文模式,在线缓存可随时清理。
struct OnlineBookMeta: Codable, Equatable {
    var sourceID: String
    var sourceBookID: String
    var title: String
    var author: String
    var chapters: [OnlineChapterRef]
    var updatedAt: Date

    var chapterCount: Int { chapters.count }
}

struct OnlineChapterRef: Codable, Equatable {
    var id: String
    var title: String
}

final class OnlineChapterStore {
    static let shared = OnlineChapterStore()

    private let fm = FileManager.default

    private init() {}

    // MARK: - 路径

    private func booksRoot() -> URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Books", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func directory(for bookID: String) -> URL {
        booksRoot()
            .appendingPathComponent(BookContentStore.safeComponent(bookID), isDirectory: true)
            .appendingPathComponent("online", isDirectory: true)
    }

    private func metaURL(_ bookID: String) -> URL {
        directory(for: bookID).appendingPathComponent("meta.json")
    }

    private func chapterURL(_ bookID: String, index: Int) -> URL {
        directory(for: bookID).appendingPathComponent(String(format: "%05d.txt", index))
    }

    // MARK: - 目录

    func saveMeta(_ meta: OnlineBookMeta, bookID: String) throws {
        let dir = directory(for: bookID)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var m = meta
        m.updatedAt = Date()
        try JSONEncoder().encode(m).write(to: metaURL(bookID), options: .atomic)
    }

    func meta(bookID: String) -> OnlineBookMeta? {
        guard let data = try? Data(contentsOf: metaURL(bookID)) else { return nil }
        return try? JSONDecoder().decode(OnlineBookMeta.self, from: data)
    }

    func hasMeta(bookID: String) -> Bool {
        fm.fileExists(atPath: metaURL(bookID).path)
    }

    // MARK: - 章节

    func chapterText(bookID: String, index: Int) -> String? {
        let url = chapterURL(bookID, index: index)
        guard fm.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveChapter(bookID: String, index: Int, text: String) {
        let dir = directory(for: bookID)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: chapterURL(bookID, index: index), atomically: true, encoding: .utf8)
    }

    func cachedChapterCount(bookID: String) -> Int {
        guard let files = try? fm.contentsOfDirectory(atPath: directory(for: bookID).path) else { return 0 }
        return files.filter { $0.hasSuffix(".txt") }.count
    }

    func deleteAll(bookID: String) {
        try? fm.removeItem(at: directory(for: bookID))
    }
}
