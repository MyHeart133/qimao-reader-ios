import Foundation
import SwiftData

/// 图书馆服务:统一「内容落盘 + 书架入库」的事务边界
@MainActor
enum LibraryService {

    /// 将导入结果写入书架(内容落盘 → SwiftData 记录)
    @discardableResult
    static func addImported(
        _ imported: ImportedBook,
        sourceID: String,
        context: ModelContext
    ) throws -> ShelfBook {
        let bookID = UUID().uuidString
        try BookContentStore.shared.save(text: imported.text, bookID: bookID)

        let book = ShelfBook(
            id: bookID,
            title: imported.title,
            author: imported.author,
            sourceID: sourceID,
            localPath: "Books/\(BookContentStore.safeComponent(bookID))/content.txt",
            coverPath: nil,
            intro: "",
            contentSignature: nil
        )
        context.insert(book)
        try context.save()
        return book
    }

    /// 在线书籍入架:目录落盘 + 书架记录(不下载全文,边读边缓存)
    ///
    /// 书架 ID 固定为 `sourceID:sourceBookID`(stableID),
    /// 之后整本缓存完成时按同一 ID 升级为离线书,不产生重复条目。
    @discardableResult
    static func ensureOnlineShelfBook(
        book: SourceBook,
        meta: OnlineBookMeta,
        context: ModelContext
    ) throws -> ShelfBook {
        let id = book.stableID
        try OnlineChapterStore.shared.saveMeta(meta, bookID: id)

        if let existing = shelfBook(id: id, context: context) {
            existing.title = book.title
            existing.author = book.author
            if existing.intro.isEmpty {
                existing.intro = book.summary ?? ""
            }
            try? context.save()
            return existing
        }

        let shelf = ShelfBook(
            id: id,
            title: book.title,
            author: book.author,
            sourceID: book.sourceID,
            sourceBookID: book.sourceBookID,
            localPath: nil,
            intro: book.summary ?? ""
        )
        context.insert(shelf)
        try context.save()
        return shelf
    }

    static func shelfBook(id: String, context: ModelContext) -> ShelfBook? {
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// 从书架移除(保留本地文件;若文件被其它记录引用则不受影响)
    static func removeFromShelf(_ book: ShelfBook, context: ModelContext) {
        context.delete(book)
        try? context.save()
    }

    /// 彻底删除(记录 + 本地内容文件 + 阅读进度)
    static func deleteCompletely(_ book: ShelfBook, context: ModelContext) {
        let bookID = book.id
        context.delete(book)

        let descriptor = FetchDescriptor<ReadingPosition>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        if let positions = try? context.fetch(descriptor) {
            for p in positions {
                context.delete(p)
            }
        }
        try? context.save()
        try? BookContentStore.shared.delete(bookID: bookID)   // 目录整删(含在线缓存)
    }
}
