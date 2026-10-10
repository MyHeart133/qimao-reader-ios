import Foundation

/// URLSession 流式下载实现
///
/// - 支持 HTTP Range 断点续传(若服务器支持,206 响应)
/// - If-Range + ETag 防止新旧版本拼接(服务器换版本时自动从头)
/// - 取消通过 Swift Task 取消传播
final class URLSessionDownloadEngine: DownloadEngineProtocol {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
    }

    func download(
        _ request: DownloadRequest,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> DownloadOutcome {
        let fm = FileManager.default

        // 以文件实际大小为准计算续传点
        let actualSize: Int64
        if fm.fileExists(atPath: request.partialFileURL.path),
           let attrs = try? fm.attributesOfItem(atPath: request.partialFileURL.path),
           let size = attrs[.size] as? NSNumber {
            actualSize = size.int64Value
        } else {
            actualSize = 0
        }
        let resumeFrom = min(request.resumeFrom, actualSize)

        var urlRequest = URLRequest(url: request.url)
        urlRequest.setValue("NovelFlow/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        if resumeFrom > 0 {
            urlRequest.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
            if let etag = request.expectedETag {
                urlRequest.setValue(etag, forHTTPHeaderField: "If-Range")
            }
        }

        let (stream, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadEngineError.network("无 HTTP 响应")
        }
        switch http.statusCode {
        case 200, 206:
            break
        case 416:
            throw DownloadEngineError.rangeNotSatisfiable
        default:
            throw DownloadEngineError.http(http.statusCode)
        }

        let isResuming = http.statusCode == 206
        let serverRemaining = http.expectedContentLength
        let totalBytes: Int64 = isResuming
            ? (serverRemaining > 0 ? resumeFrom + serverRemaining : -1)
            : serverRemaining
        let etag = http.value(forHTTPHeaderField: "ETag")
        let acceptsRanges = http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"

        // 打开写入句柄
        try? fm.createDirectory(
            at: request.partialFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !isResuming {
            if fm.fileExists(atPath: request.partialFileURL.path) {
                try? fm.removeItem(at: request.partialFileURL)
            }
            guard fm.createFile(atPath: request.partialFileURL.path, contents: nil) else {
                throw DownloadEngineError.storage
            }
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: request.partialFileURL)
        } catch {
            throw DownloadEngineError.storage
        }
        defer { try? handle.close() }

        var received: Int64 = isResuming ? resumeFrom : 0
        if isResuming {
            do {
                try handle.seekToEnd()
            } catch {
                throw DownloadEngineError.storage
            }
        }
        progress(received, totalBytes)

        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)
        var sinceCancelCheck = 0

        for try await byte in stream {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(received, totalBytes)
                sinceCancelCheck += 1
                if sinceCancelCheck >= 4 {
                    sinceCancelCheck = 0
                    try Task.checkCancellation()
                }
            }
        }
        if !buffer.isEmpty {
            do {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
            } catch {
                throw DownloadEngineError.storage
            }
        }
        do {
            try handle.synchronize()
        } catch {
            // 同步失败不致命,文件已写入
        }
        progress(received, totalBytes)

        return DownloadOutcome(
            partialFileURL: request.partialFileURL,
            receivedBytes: received,
            totalBytes: totalBytes,
            etag: etag,
            serverSupportsRange: isResuming || acceptsRanges
        )
    }
}
