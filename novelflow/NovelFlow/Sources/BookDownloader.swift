import Foundation
import SwiftData
import SwiftUI

/// 下载任务(下载 → 导入解析 → 入库)
struct DownloadJob: Identifiable, Equatable {
    var id: String
    var title: String
    var phase: String
    var progress: Double
    var error: String?

    var isFinished: Bool { phase == "完成" || phase == "失败" }
}

/// 全局下载器(本轮:整本直链下载;断点续传在 P3 下载中心阶段落地)
@MainActor
final class BookDownloader: ObservableObject {
    static let shared = BookDownloader()

    @Published private(set) var job: DownloadJob?

    private init() {}

    var isBusy: Bool { job != nil && !(job?.isFinished ?? true) }

    func clearFinished() {
        if job?.isFinished == true {
            job = nil
        }
    }

    /// 下载开放来源书籍并加入书架
    func download(_ sourceBook: SourceBook, context: ModelContext) {
        guard !isBusy else { return }
        guard let urlString = sourceBook.downloadURL, let url = URL(string: urlString) else {
            job = DownloadJob(id: sourceBook.id, title: sourceBook.title, phase: "失败",
                              progress: 0, error: "该来源未提供可下载地址")
            return
        }

        job = DownloadJob(id: sourceBook.id, title: sourceBook.title, phase: "下载中", progress: 0, error: nil)

        Task {
            do {
                // 1) 下载
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw SourceError.network("HTTP \(http.statusCode)")
                }
                guard !data.isEmpty else { throw ImportError.emptyBook }
                self.job?.progress = 0.5
                self.job?.phase = "解析中"

                // 2) 解析(后台化:文本处理不占主线程)
                let fileName = "\(sourceBook.title).\(sourceBook.downloadFormat ?? "txt")"
                let imported: ImportedBook = try await Task.detached(priority: .userInitiated) {
                    if sourceBook.downloadFormat == "epub" || urlString.lowercased().hasSuffix(".epub") {
                        return try LocalImporter.importEPUB(data: data, name: fileName)
                    } else {
                        return try LocalImporter.importTXT(data: data, name: fileName)
                    }
                }.value
                self.job?.progress = 0.8

                // 3) 入库(标题/作者以来源元数据优先,文本解析结果补齐)
                var merged = imported
                if merged.title.isEmpty || merged.title.count < 2 {
                    merged.title = sourceBook.title
                }
                if merged.author.isEmpty {
                    merged.author = sourceBook.author
                }
                let book = try LibraryService.addImported(merged, sourceID: sourceBook.sourceID, context: context)
                book.intro = sourceBook.summary ?? ""
                try? context.save()

                self.job?.progress = 1.0
                self.job?.phase = "完成"
            } catch {
                self.job?.phase = "失败"
                self.job?.error = error.localizedDescription
            }
        }
    }
}
