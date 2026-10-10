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
        try? BookContentStore.shared.delete(bookID: bookID)
    }
}
