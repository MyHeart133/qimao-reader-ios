import Foundation

// MARK: - 任务状态机

enum DownloadState: String, Codable, Equatable {
    case queued       // 等待中
    case downloading  // 下载中
    case paused       // 已暂停
    case completed    // 已完成
    case failed       // 失败
    case cancelled    // 已取消

    var isActive: Bool { self == .queued || self == .downloading }
    var isFinished: Bool { self == .completed || self == .failed || self == .cancelled }

    var displayName: String {
        switch self {
        case .queued: return "等待中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

/// 下载任务(Codable:用于持久化,重启后恢复列表)
struct DownloadTask: Identifiable, Equatable, Codable {
    var id: String               // = sourceBook.stableID
    var title: String
    var author: String
    var summary: String?
    var sourceID: String
    var sourceBookID: String
    var url: String
    var format: String           // txt / epub
    var state: DownloadState
    var receivedBytes: Int64
    var totalBytes: Int64        // -1 = 未知
    var etag: String?
    var error: String?
    var speedBytesPerSec: Double
    var createdAt: Date
    var updatedAt: Date

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(receivedBytes) / Double(totalBytes))
    }

    var progressText: String {
        let mb = 1024.0 * 1024.0
        if totalBytes > 0 {
            return String(format: "%.1f / %.1f MB", Double(receivedBytes) / mb, Double(totalBytes) / mb)
        }
        if receivedBytes > 0 {
            return String(format: "%.1f MB", Double(receivedBytes) / mb)
        }
        return ""
    }

    var speedText: String {
        guard state == .downloading, speedBytesPerSec > 1 else { return "" }
        let mb = 1024.0 * 1024.0
        if speedBytesPerSec > mb {
            return String(format: "%.1f MB/s", speedBytesPerSec / mb)
        }
        return String(format: "%.0f KB/s", speedBytesPerSec / 1024.0)
    }

    static func from(_ book: SourceBook) -> DownloadTask? {
        guard let url = book.downloadURL else { return nil }
        return DownloadTask(
            id: book.id,
            title: book.title,
            author: book.author,
            summary: book.summary,
            sourceID: book.sourceID,
            sourceBookID: book.sourceBookID,
            url: url,
            format: book.downloadFormat ?? "txt",
            state: .queued,
            receivedBytes: 0,
            totalBytes: -1,
            etag: nil,
            error: nil,
            speedBytesPerSec: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// 重试时重建最小 SourceBook
    func toSourceBook() -> SourceBook {
        SourceBook(
            sourceID: sourceID,
            sourceBookID: sourceBookID,
            title: title,
            author: author,
            cover: nil,
            language: nil,
            summary: summary,
            subjects: [],
            downloadCount: nil,
            downloadURL: url,
            downloadFormat: format,
            externalURL: nil
        )
    }
}

enum DownloadFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "进行中"
    case completed = "已完成"
    case failed = "失败"

    var id: String { rawValue }

    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .all: return true
        case .active: return task.state.isActive || task.state == .paused
        case .completed: return task.state == .completed
        case .failed: return task.state == .failed || task.state == .cancelled
        }
    }
}

// MARK: - 引擎接口

struct DownloadRequest {
    var url: URL
    /// 部分文件目标路径(断点续传基于它)
    var partialFileURL: URL
    /// 期望从该字节继续(以文件实际大小为准)
    var resumeFrom: Int64
    /// 上次下载的 ETag,用于 If-Range 版本校验
    var expectedETag: String?
}

struct DownloadOutcome {
    var partialFileURL: URL
    var receivedBytes: Int64
    var totalBytes: Int64
    var etag: String?
    var serverSupportsRange: Bool
}

enum DownloadEngineError: LocalizedError, Equatable {
    case http(Int)
    case network(String)
    case storage
    case rangeNotSatisfiable

    var errorDescription: String? {
        switch self {
        case .http(let code): return "服务器返回 HTTP \(code)"
        case .network(let m): return "网络错误：\(m)"
        case .storage: return "无法写入下载文件(存储空间不足?)"
        case .rangeNotSatisfiable: return "断点数据失效,请重试"
        }
    }
}

/// 传输层抽象(可注入 Mock 做状态机测试)
protocol DownloadEngineProtocol {
    func download(
        _ request: DownloadRequest,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> DownloadOutcome
}
