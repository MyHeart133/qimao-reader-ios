import Foundation
import SwiftData

/// 书架书籍(P0 基础模型;导入与书源阶段继续扩展)
@Model
final class ShelfBook {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    /// 来源标识:"local-import" / "gutenberg" / "qimao" / ...
    var sourceID: String
    /// 来源站内书籍标识(在线书必备;整本缓存后仍保留)
    var sourceBookID: String?
    /// 本地相对路径(App 沙盒内);nil = 在线书籍(边读边缓存)
    var localPath: String?
    var coverPath: String?
    var intro: String
    var addedAt: Date
    var lastReadAt: Date?
    /// 内容标识:用于阅读锚点失效检测(内容变化后旧锚点不适用)
    var contentSignature: String?

    /// 在线书:有来源标识、无本地全文
    var isOnline: Bool { localPath == nil && sourceBookID != nil }

    init(
        id: String,
        title: String,
        author: String = "",
        sourceID: String,
        sourceBookID: String? = nil,
        localPath: String? = nil,
        coverPath: String? = nil,
        intro: String = "",
        contentSignature: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceID = sourceID
        self.sourceBookID = sourceBookID
        self.localPath = localPath
        self.coverPath = coverPath
        self.intro = intro
        self.addedAt = Date()
        self.lastReadAt = nil
        self.contentSignature = contentSignature
    }
}

/// 阅读位置(稳定锚点;页码仅展示)
@Model
final class ReadingPosition {
    @Attribute(.unique) var bookID: String
    var chapterIndex: Int
    /// UTF-16 文本偏移(章节内),重新分页后可恢复
    var anchorOffset: Int
    var percentage: Double
    var updatedAt: Date

    init(bookID: String, chapterIndex: Int = 0, anchorOffset: Int = 0, percentage: Double = 0) {
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.anchorOffset = anchorOffset
        self.percentage = percentage
        self.updatedAt = Date()
    }
}

/// 书签(章内锚点 + 摘录;按书隔离)
@Model
final class Bookmark {
    @Attribute(.unique) var id: String
    var bookID: String
    var chapterIndex: Int
    var anchorOffset: Int
    var chapterTitle: String
    var excerpt: String
    var createdAt: Date

    init(bookID: String, chapterIndex: Int, anchorOffset: Int, chapterTitle: String, excerpt: String) {
        self.id = "\(bookID)#\(chapterIndex)#\(anchorOffset)"
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.anchorOffset = anchorOffset
        self.chapterTitle = chapterTitle
        self.excerpt = excerpt
        self.createdAt = Date()
    }
}
