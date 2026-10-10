import Foundation
import SwiftUI

// MARK: - 书架数据

struct ShelfBook: Codable, Identifiable {
    var id: String
    var title: String
    var author: String
    var cover: String
    var intro: String
    var chapterCount: Int
    var downloaded: Bool
    var savedName: String
    var lastChapterIndex: Int
    var updatedAt: Date
}

final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published var books: [ShelfBook] = []

    private let key = "qimao_shelf_v1"

    private init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ShelfBook].self, from: data) else { return }
        books = list
    }

    func save() {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ b: ShelfBook) {
        if let i = books.firstIndex(where: { $0.id == b.id }) {
            var nb = b
            nb.lastChapterIndex = max(b.lastChapterIndex, books[i].lastChapterIndex)
            books[i] = nb
        } else {
            books.insert(b, at: 0)
        }
        save()
    }

    func updateProgress(bookID: String, chapterIndex: Int) {
        guard let i = books.firstIndex(where: { $0.id == bookID }) else { return }
        if chapterIndex > books[i].lastChapterIndex {
            books[i].lastChapterIndex = chapterIndex
            books[i].updatedAt = Date()
            save()
        }
    }

    func book(_ id: String) -> ShelfBook? {
        books.first { $0.id == id }
    }

    func remove(_ id: String) {
        books.removeAll { $0.id == id }
        save()
    }
}

// MARK: - 下载管理(全局单例,进度随处可看)

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published var active = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var finishedMessage: String?

    private init() {}

    func download(book: QBook, chapters: [QChapter]) {
        guard !active, !chapters.isEmpty else { return }
        active = true
        progress = 0
        statusText = "准备下载…"

        Task {
            var acc: [(String, String)] = []
            var failed = 0
            let total = chapters.count

            for (i, ch) in chapters.enumerated() {
                do {
                    let text = try await QimaoAPI.shared.chapterText(book.id, chapterID: ch.id)
                    acc.append((ch.title, text))
                } catch {
                    failed += 1
                }
                progress = Double(i + 1) / Double(total)
                statusText = "[\(i + 1)/\(total)] \(ch.title.prefix(18))"
                if i % 4 == 3 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }

            let txtURL = Exporter.saveTXT(book: book, chapters: acc)
            let cover = await Exporter.fetchCover(book.cover)
            let epubURL = Exporter.saveEPUB(book: book, chapters: acc, cover: cover)

            var name = book.title
            if let t = txtURL {
                name = t.deletingPathExtension().lastPathComponent
            }

            ShelfStore.shared.upsert(ShelfBook(
                id: book.id,
                title: book.title,
                author: book.author,
                cover: book.cover,
                intro: book.intro,
                chapterCount: total,
                downloaded: true,
                savedName: name,
                lastChapterIndex: ShelfStore.shared.book(book.id)?.lastChapterIndex ?? 1,
                updatedAt: Date()
            ))

            var msg = "已保存 \(acc.count)/\(total) 章"
            if failed > 0 { msg += "，失败 \(failed) 章" }
            if let e = epubURL {
                msg += "\n\n文件：\(e.lastPathComponent)\n路径:文件 App → 我的 iPhone → 七猫阅读器 → qimao"
            } else {
                msg += "\n\n保存失败,请检查存储空间"
            }
            finishedMessage = msg
            statusText = "完成"
            active = false
        }
    }
}
